# agent/collectors/network_stats.py
"""
Network Statistics Collector for Zero Trust Agent
Collects network connection patterns and traffic metrics

Collected signals:
- Active connections count
- Connection by state (ESTABLISHED, TIME_WAIT, etc.)
- Traffic volume per interface
- Connection patterns (frequency, peers)
"""

import subprocess
import logging
import re
from typing import Dict, List, Any, Optional
from collections import Counter

logger = logging.getLogger('zt-agent.collectors.network')


class NetworkStatsCollector:
    """
    Collects network statistics for trust scoring
    Monitors connection patterns and traffic anomalies
    """

    def __init__(self, interface: str = "wg0"):
        self.interface = interface
        self.previous_rx_bytes = 0
        self.previous_tx_bytes = 0

    def collect_all(self) -> Dict[str, Any]:
        """Collect all network statistics"""
        return {
            'connections': self._collect_connections(),
            'traffic': self._collect_traffic_stats(),
            'wireguard': self._collect_wireguard_stats(),
            'interfaces': self._collect_interface_stats()
        }

    def _collect_connections(self) -> Dict[str, Any]:
        """Collect connection statistics using ss command"""
        result = {
            'total': 0,
            'established': 0,
            'listening': 0,
            'time_wait': 0,
            'close_wait': 0,
            'by_state': {},
            'unique_peers': 0,
            'top_ports': []
        }

        try:
            # Get all TCP connections
            output = self._run_command(['ss', '-tan'])
            if not output:
                return result

            lines = output.strip().split('\n')[1:]  # Skip header
            result['total'] = len(lines)

            states = Counter()
            peers = set()
            ports = Counter()

            for line in lines:
                parts = line.split()
                if len(parts) >= 5:
                    state = parts[0]
                    states[state] += 1

                    # Extract peer IP
                    peer_addr = parts[4]
                    if ':' in peer_addr:
                        ip = peer_addr.rsplit(':', 1)[0]
                        port = peer_addr.rsplit(':', 1)[1]
                        if ip not in ['*', '0.0.0.0', '127.0.0.1', '[::]']:
                            peers.add(ip)
                        if port.isdigit():
                            ports[port] += 1

            result['by_state'] = dict(states)
            result['established'] = states.get('ESTAB', 0)
            result['listening'] = states.get('LISTEN', 0)
            result['time_wait'] = states.get('TIME-WAIT', 0)
            result['close_wait'] = states.get('CLOSE-WAIT', 0)
            result['unique_peers'] = len(peers)
            result['top_ports'] = [p[0] for p in ports.most_common(10)]

        except Exception as e:
            logger.warning(f"Error collecting connections: {e}")

        return result

    def _collect_traffic_stats(self) -> Dict[str, Any]:
        """Collect traffic statistics for wg0 interface"""
        result = {
            'interface': self.interface,
            'rx_bytes': 0,
            'tx_bytes': 0,
            'rx_packets': 0,
            'tx_packets': 0,
            'rx_rate_bps': 0,
            'tx_rate_bps': 0
        }

        try:
            # Read from /sys/class/net
            base_path = f'/sys/class/net/{self.interface}/statistics'

            with open(f'{base_path}/rx_bytes', 'r') as f:
                result['rx_bytes'] = int(f.read().strip())
            with open(f'{base_path}/tx_bytes', 'r') as f:
                result['tx_bytes'] = int(f.read().strip())
            with open(f'{base_path}/rx_packets', 'r') as f:
                result['rx_packets'] = int(f.read().strip())
            with open(f'{base_path}/tx_packets', 'r') as f:
                result['tx_packets'] = int(f.read().strip())

            # Calculate rate (bytes per second since last collection)
            # This is approximate; needs time tracking for accuracy
            if self.previous_rx_bytes > 0:
                result['rx_rate_bps'] = max(0, result['rx_bytes'] - self.previous_rx_bytes)
            if self.previous_tx_bytes > 0:
                result['tx_rate_bps'] = max(0, result['tx_bytes'] - self.previous_tx_bytes)

            self.previous_rx_bytes = result['rx_bytes']
            self.previous_tx_bytes = result['tx_bytes']

        except FileNotFoundError:
            logger.debug(f"Interface {self.interface} not found")
        except Exception as e:
            logger.warning(f"Error collecting traffic stats: {e}")

        return result

    def _collect_wireguard_stats(self) -> Dict[str, Any]:
        """Collect WireGuard-specific statistics"""
        result = {
            'peers': [],
            'total_peers': 0,
            'active_peers': 0,
            'total_rx_bytes': 0,
            'total_tx_bytes': 0
        }

        try:
            output = self._run_command(['wg', 'show', self.interface, 'dump'])
            if not output:
                return result

            lines = output.strip().split('\n')

            # First line is interface info, rest are peers
            for line in lines[1:]:
                parts = line.split('\t')
                if len(parts) >= 6:
                    peer_info = {
                        'public_key': parts[0][:20] + '...',  # Truncate for privacy
                        'endpoint': parts[2] if parts[2] != '(none)' else None,
                        'allowed_ips': parts[3],
                        'latest_handshake': int(parts[4]) if parts[4] != '0' else None,
                        'rx_bytes': int(parts[5]),
                        'tx_bytes': int(parts[6]) if len(parts) > 6 else 0
                    }

                    result['peers'].append(peer_info)
                    result['total_rx_bytes'] += peer_info['rx_bytes']
                    result['total_tx_bytes'] += peer_info['tx_bytes']

                    # Active if handshake within last 3 minutes
                    if peer_info['latest_handshake'] and peer_info['latest_handshake'] > 0:
                        import time
                        if (time.time() - peer_info['latest_handshake']) < 180:
                            result['active_peers'] += 1

            result['total_peers'] = len(result['peers'])

        except Exception as e:
            logger.warning(f"Error collecting WireGuard stats: {e}")

        return result

    def _collect_interface_stats(self) -> Dict[str, Any]:
        """Collect general interface statistics"""
        result = {
            'interfaces': [],
            'total_interfaces': 0
        }

        try:
            output = self._run_command(['ip', '-s', 'link'])
            if not output:
                return result

            # Parse interface info
            current_iface = None
            for line in output.split('\n'):
                # Interface line
                match = re.match(r'^\d+:\s+(\S+):', line)
                if match:
                    if current_iface:
                        result['interfaces'].append(current_iface)
                    current_iface = {
                        'name': match.group(1),
                        'state': 'unknown',
                        'rx_bytes': 0,
                        'tx_bytes': 0
                    }
                    # Check state
                    if 'UP' in line:
                        current_iface['state'] = 'up'
                    elif 'DOWN' in line:
                        current_iface['state'] = 'down'

                # RX line
                elif current_iface and 'RX:' in line:
                    # Next line has the values
                    pass
                elif current_iface and re.match(r'^\s+\d+', line):
                    parts = line.split()
                    if len(parts) >= 1:
                        if current_iface.get('_next_is_rx', False):
                            current_iface['rx_bytes'] = int(parts[0])
                            current_iface['_next_is_tx'] = True
                            current_iface['_next_is_rx'] = False
                        elif current_iface.get('_next_is_tx', False):
                            current_iface['tx_bytes'] = int(parts[0])
                            current_iface['_next_is_tx'] = False

            if current_iface:
                result['interfaces'].append(current_iface)

            result['total_interfaces'] = len(result['interfaces'])

        except Exception as e:
            logger.warning(f"Error collecting interface stats: {e}")

        return result

    def _run_command(self, cmd: List[str], timeout: int = 10) -> Optional[str]:
        """Run a shell command and return output"""
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return result.stdout if result.returncode == 0 else None
        except subprocess.TimeoutExpired:
            logger.warning(f"Command timed out: {' '.join(cmd)}")
            return None
        except Exception as e:
            logger.debug(f"Command failed: {' '.join(cmd)}: {e}")
            return None


# Module-level functions
def collect_network_stats() -> Dict[str, Any]:
    """Collect all network statistics"""
    collector = NetworkStatsCollector()
    return collector.collect_all()


def get_connection_count() -> int:
    """Get total connection count"""
    collector = NetworkStatsCollector()
    stats = collector._collect_connections()
    return stats.get('total', 0)


def get_wireguard_peers() -> int:
    """Get number of WireGuard peers"""
    collector = NetworkStatsCollector()
    stats = collector._collect_wireguard_stats()
    return stats.get('total_peers', 0)
