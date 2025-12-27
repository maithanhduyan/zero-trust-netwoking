# control-plane/core/wireguard_service.py
"""
WireGuard Service for Hub
Manages WireGuard peers on the Hub server
"""

import subprocess
import logging
from typing import Optional

logger = logging.getLogger(__name__)


class WireGuardService:
    """
    Manages WireGuard interface on Hub server

    Responsibilities:
    - Add peers when nodes register
    - Remove peers when nodes are revoked
    - Save config to persist peers
    """

    def __init__(self, interface: str = "wg0"):
        self.interface = interface

    def _run(self, cmd: list, check: bool = True, timeout: int = 10) -> subprocess.CompletedProcess:
        """Run shell command"""
        logger.debug(f"Running: {' '.join(cmd)}")
        return subprocess.run(
            cmd,
            check=check,
            capture_output=True,
            text=True,
            timeout=timeout
        )

    def is_interface_up(self) -> bool:
        """Check if WireGuard interface is running"""
        try:
            result = self._run(["wg", "show", self.interface], check=False)
            return result.returncode == 0
        except Exception:
            return False

    def add_peer(
        self,
        public_key: str,
        allowed_ips: str,
        save_config: bool = True
    ) -> bool:
        """
        Add a peer to WireGuard interface

        Args:
            public_key: WireGuard public key of the peer
            allowed_ips: Allowed IPs for the peer (e.g., "10.10.0.2/32")
            save_config: Whether to save config to file for persistence

        Returns:
            True if successful, False otherwise
        """
        if not self.is_interface_up():
            logger.warning(f"WireGuard interface {self.interface} is not running")
            return False

        try:
            # Add peer
            self._run([
                "wg", "set", self.interface,
                "peer", public_key,
                "allowed-ips", allowed_ips
            ])

            logger.info(f"Added peer: {public_key[:20]}... -> {allowed_ips}")

            # Save config to persist after reboot
            if save_config:
                self.save_config()

            return True

        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to add peer: {e.stderr}")
            return False
        except subprocess.TimeoutExpired:
            logger.error("Command timed out")
            return False
        except Exception as e:
            logger.error(f"Unexpected error adding peer: {e}")
            return False

    def remove_peer(self, public_key: str, save_config: bool = True) -> bool:
        """
        Remove a peer from WireGuard interface

        Args:
            public_key: WireGuard public key of the peer to remove
            save_config: Whether to save config to file for persistence

        Returns:
            True if successful, False otherwise
        """
        if not self.is_interface_up():
            logger.warning(f"WireGuard interface {self.interface} is not running")
            return False

        try:
            self._run([
                "wg", "set", self.interface,
                "peer", public_key,
                "remove"
            ])

            logger.info(f"Removed peer: {public_key[:20]}...")

            if save_config:
                self.save_config()

            return True

        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to remove peer: {e.stderr}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error removing peer: {e}")
            return False

    def save_config(self) -> bool:
        """Save current WireGuard config to file"""
        try:
            self._run(["wg-quick", "save", self.interface])
            logger.debug(f"Saved WireGuard config for {self.interface}")
            return True
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to save config: {e.stderr}")
            return False
        except Exception as e:
            logger.warning(f"Failed to save config: {e}")
            return False

    def get_peers(self) -> list:
        """Get list of current peers"""
        try:
            result = self._run(["wg", "show", self.interface, "dump"])
            peers = []

            for line in result.stdout.strip().split('\n')[1:]:  # Skip interface line
                parts = line.split('\t')
                if len(parts) >= 4:
                    peers.append({
                        'public_key': parts[0],
                        'endpoint': parts[2] if parts[2] != '(none)' else None,
                        'allowed_ips': parts[3],
                        'latest_handshake': parts[4] if len(parts) > 4 else None,
                    })

            return peers

        except Exception as e:
            logger.error(f"Failed to get peers: {e}")
            return []

    def peer_exists(self, public_key: str) -> bool:
        """Check if a peer already exists"""
        peers = self.get_peers()
        return any(p['public_key'] == public_key for p in peers)


# Singleton instance
wireguard_service = WireGuardService()
