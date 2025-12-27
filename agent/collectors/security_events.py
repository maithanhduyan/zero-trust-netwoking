# agent/collectors/security_events.py
"""
Security Events Collector for Zero Trust Agent
Collects security-relevant events for Dynamic Trust Scoring

Collected signals:
- Failed SSH login attempts
- Firewall rule violations
- WireGuard handshake failures
- Suspicious process detection
- Authentication events
"""

import os
import re
import subprocess
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from pathlib import Path

logger = logging.getLogger('zt-agent.collectors.security')


class SecurityEventsCollector:
    """
    Collects security events from system logs and services
    Used for Dynamic Trust Score calculation
    """

    def __init__(self):
        self.auth_log_paths = [
            '/var/log/auth.log',      # Debian/Ubuntu
            '/var/log/secure',         # RHEL/CentOS
            '/var/log/messages',       # Fallback
        ]
        self.syslog_path = '/var/log/syslog'
        self.last_collection_time = datetime.utcnow() - timedelta(minutes=5)

    def collect_all(self) -> Dict[str, Any]:
        """
        Collect all security events
        Returns aggregated security metrics
        """
        now = datetime.utcnow()

        events = {
            'timestamp': now.isoformat(),
            'collection_period_seconds': (now - self.last_collection_time).total_seconds(),
            'ssh': self._collect_ssh_events(),
            'firewall': self._collect_firewall_events(),
            'wireguard': self._collect_wireguard_events(),
            'processes': self._collect_suspicious_processes(),
            'summary': {}
        }

        # Calculate summary
        events['summary'] = {
            'total_failures': (
                events['ssh'].get('failed_attempts', 0) +
                events['firewall'].get('blocked_connections', 0) +
                events['wireguard'].get('handshake_failures', 0)
            ),
            'risk_level': self._calculate_risk_level(events),
            'risk_factors': self._get_risk_factors(events)
        }

        self.last_collection_time = now
        return events

    def _collect_ssh_events(self) -> Dict[str, Any]:
        """Collect SSH authentication events from auth.log"""
        result = {
            'failed_attempts': 0,
            'successful_logins': 0,
            'failed_ips': [],
            'brute_force_detected': False
        }

        auth_log = self._find_auth_log()
        if not auth_log:
            logger.debug("No auth log found")
            return result

        try:
            # Use journalctl if available (more reliable)
            if self._has_journalctl():
                output = self._run_command([
                    'journalctl', '-u', 'ssh', '-u', 'sshd',
                    '--since', '5 minutes ago',
                    '--no-pager', '-q'
                ])
            else:
                # Fallback to reading log file
                output = self._tail_log(auth_log, 200)

            if not output:
                return result

            # Parse failed attempts
            failed_pattern = re.compile(
                r'Failed password for (?:invalid user )?(\S+) from (\d+\.\d+\.\d+\.\d+)'
            )
            success_pattern = re.compile(
                r'Accepted (?:password|publickey) for (\S+) from (\d+\.\d+\.\d+\.\d+)'
            )

            failed_ips = {}
            for line in output.split('\n'):
                # Count failed attempts
                failed_match = failed_pattern.search(line)
                if failed_match:
                    result['failed_attempts'] += 1
                    ip = failed_match.group(2)
                    failed_ips[ip] = failed_ips.get(ip, 0) + 1

                # Count successful logins
                if success_pattern.search(line):
                    result['successful_logins'] += 1

            # Detect brute force (>10 attempts from same IP)
            result['failed_ips'] = list(failed_ips.keys())[:10]  # Limit to 10 IPs
            result['brute_force_detected'] = any(count > 10 for count in failed_ips.values())

        except Exception as e:
            logger.warning(f"Error collecting SSH events: {e}")

        return result

    def _collect_firewall_events(self) -> Dict[str, Any]:
        """Collect firewall (iptables) drop/reject events"""
        result = {
            'blocked_connections': 0,
            'dropped_by_zt_acl': 0,
            'port_scan_detected': False,
            'blocked_ports': []
        }

        try:
            # Check kernel log for iptables drops
            if self._has_journalctl():
                output = self._run_command([
                    'journalctl', '-k',
                    '--since', '5 minutes ago',
                    '--no-pager', '-q', '--grep', r'DROP\|REJECT\|ZT_ACL'
                ])
            else:
                output = self._run_command([
                    'dmesg', '--time-format', 'iso'
                ]) or ""
                # Filter for firewall events
                output = '\n'.join(
                    line for line in output.split('\n')
                    if 'DROP' in line or 'REJECT' in line or 'ZT_ACL' in line
                )

            if output:
                lines = output.strip().split('\n')
                result['blocked_connections'] = len([l for l in lines if l])
                result['dropped_by_zt_acl'] = len([l for l in lines if 'ZT_ACL' in l])

                # Extract blocked ports
                port_pattern = re.compile(r'DPT=(\d+)')
                ports = port_pattern.findall(output)
                result['blocked_ports'] = list(set(ports))[:20]

                # Detect port scan (many different ports from same source)
                result['port_scan_detected'] = len(set(ports)) > 15

        except Exception as e:
            logger.warning(f"Error collecting firewall events: {e}")

        return result

    def _collect_wireguard_events(self) -> Dict[str, Any]:
        """Collect WireGuard connection events"""
        result = {
            'handshake_failures': 0,
            'successful_handshakes': 0,
            'peers_connected': 0,
            'last_handshake_seconds': None
        }

        try:
            # Get WireGuard interface status
            wg_output = self._run_command(['wg', 'show', 'wg0'])
            if wg_output:
                # Count peers with recent handshake
                handshake_pattern = re.compile(r'latest handshake: (\d+) (second|minute|hour)')
                matches = handshake_pattern.findall(wg_output)

                result['peers_connected'] = len(matches)

                if matches:
                    # Get most recent handshake
                    for value, unit in matches:
                        seconds = int(value)
                        if unit == 'minute':
                            seconds *= 60
                        elif unit == 'hour':
                            seconds *= 3600

                        if result['last_handshake_seconds'] is None:
                            result['last_handshake_seconds'] = seconds
                        else:
                            result['last_handshake_seconds'] = min(
                                result['last_handshake_seconds'], seconds
                            )

            # Check for handshake failures in dmesg
            if self._has_journalctl():
                wg_log = self._run_command([
                    'journalctl', '-k',
                    '--since', '5 minutes ago',
                    '--no-pager', '-q', '--grep', r'wireguard.*Invalid\|wireguard.*failed'
                ])
                if wg_log:
                    result['handshake_failures'] = len(wg_log.strip().split('\n'))

        except Exception as e:
            logger.warning(f"Error collecting WireGuard events: {e}")

        return result

    def _collect_suspicious_processes(self) -> Dict[str, Any]:
        """Detect suspicious processes running on the system"""
        result = {
            'suspicious_count': 0,
            'suspicious_names': [],
            'high_cpu_processes': [],
            'listening_ports_count': 0
        }

        # Known suspicious process patterns (basic heuristics)
        suspicious_patterns = [
            r'nc\s+-l',           # netcat listener
            r'ncat\s+-l',         # ncat listener
            r'socat\s+',          # socat
            r'cryptominer',       # crypto miner
            r'xmrig',             # XMRig miner
            r'kworker.*\[',       # Hidden kernel thread names
            r'\.\/\.',            # Hidden directory execution
        ]

        try:
            # Get process list
            ps_output = self._run_command(['ps', 'aux'])
            if ps_output:
                for pattern in suspicious_patterns:
                    if re.search(pattern, ps_output, re.IGNORECASE):
                        result['suspicious_count'] += 1
                        result['suspicious_names'].append(pattern)

            # Get high CPU processes (>80%)
            top_output = self._run_command([
                'ps', '-eo', 'pid,pcpu,comm', '--sort=-pcpu'
            ])
            if top_output:
                for line in top_output.split('\n')[1:6]:  # Top 5
                    parts = line.split()
                    if len(parts) >= 3:
                        try:
                            cpu = float(parts[1])
                            if cpu > 80:
                                result['high_cpu_processes'].append({
                                    'pid': parts[0],
                                    'cpu': cpu,
                                    'name': parts[2]
                                })
                        except ValueError:
                            pass

            # Count listening ports
            ss_output = self._run_command(['ss', '-tlnp'])
            if ss_output:
                result['listening_ports_count'] = len(ss_output.strip().split('\n')) - 1

        except Exception as e:
            logger.warning(f"Error collecting process info: {e}")

        return result

    def _calculate_risk_level(self, events: Dict) -> str:
        """
        Calculate overall risk level based on collected events
        Returns: 'low', 'medium', 'high', 'critical'
        """
        score = 0

        # SSH failures
        ssh_failures = events.get('ssh', {}).get('failed_attempts', 0)
        if ssh_failures > 50:
            score += 40
        elif ssh_failures > 20:
            score += 20
        elif ssh_failures > 5:
            score += 10

        # Brute force detection
        if events.get('ssh', {}).get('brute_force_detected'):
            score += 30

        # Firewall blocks
        blocked = events.get('firewall', {}).get('blocked_connections', 0)
        if blocked > 100:
            score += 30
        elif blocked > 20:
            score += 15

        # Port scan detection
        if events.get('firewall', {}).get('port_scan_detected'):
            score += 25

        # WireGuard failures
        wg_failures = events.get('wireguard', {}).get('handshake_failures', 0)
        if wg_failures > 10:
            score += 20
        elif wg_failures > 3:
            score += 10

        # Suspicious processes
        suspicious = events.get('processes', {}).get('suspicious_count', 0)
        if suspicious > 0:
            score += suspicious * 20

        # Determine level
        if score >= 80:
            return 'critical'
        elif score >= 50:
            return 'high'
        elif score >= 25:
            return 'medium'
        return 'low'

    def _get_risk_factors(self, events: Dict) -> List[str]:
        """Get list of specific risk factors detected"""
        factors = []

        if events.get('ssh', {}).get('brute_force_detected'):
            factors.append('ssh_brute_force')
        if events.get('ssh', {}).get('failed_attempts', 0) > 5:
            factors.append('ssh_failed_logins')
        if events.get('firewall', {}).get('port_scan_detected'):
            factors.append('port_scan')
        if events.get('firewall', {}).get('blocked_connections', 0) > 20:
            factors.append('high_blocked_connections')
        if events.get('wireguard', {}).get('handshake_failures', 0) > 3:
            factors.append('wireguard_failures')
        if events.get('processes', {}).get('suspicious_count', 0) > 0:
            factors.append('suspicious_processes')
        if events.get('processes', {}).get('high_cpu_processes'):
            factors.append('high_cpu_usage')

        return factors

    def _find_auth_log(self) -> Optional[str]:
        """Find the authentication log file"""
        for path in self.auth_log_paths:
            if os.path.exists(path) and os.access(path, os.R_OK):
                return path
        return None

    def _has_journalctl(self) -> bool:
        """Check if journalctl is available"""
        try:
            result = subprocess.run(
                ['which', 'journalctl'],
                capture_output=True,
                timeout=5
            )
            return result.returncode == 0
        except:
            return False

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

    def _tail_log(self, path: str, lines: int = 100) -> Optional[str]:
        """Read last N lines of a log file"""
        try:
            result = subprocess.run(
                ['tail', '-n', str(lines), path],
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.stdout if result.returncode == 0 else None
        except:
            return None


# Module-level functions for backward compatibility
def collect_security_events() -> Dict[str, Any]:
    """Collect all security events"""
    collector = SecurityEventsCollector()
    return collector.collect_all()


def get_ssh_failures() -> Dict[str, Any]:
    """Get SSH failure events only"""
    collector = SecurityEventsCollector()
    return collector._collect_ssh_events()


def get_firewall_events() -> Dict[str, Any]:
    """Get firewall events only"""
    collector = SecurityEventsCollector()
    return collector._collect_firewall_events()


def get_risk_level() -> str:
    """Quick risk level check"""
    events = collect_security_events()
    return events.get('summary', {}).get('risk_level', 'unknown')
