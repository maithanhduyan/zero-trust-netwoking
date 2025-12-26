# control-plane/core/ipam.py
"""
IP Address Management (IPAM) Service
Manages overlay network IP allocation for Zero Trust nodes
"""

import ipaddress
from typing import Optional, List, Tuple
from sqlalchemy.orm import Session
from datetime import datetime
import logging

from database.models import Node, IPAllocation
from config import settings

logger = logging.getLogger(__name__)


class IPAMService:
    """
    IPAM Service for managing overlay network IP allocations

    Features:
    - Automatic IP allocation from configured pool
    - Reserved IPs (network, gateway, broadcast)
    - IP release and reallocation
    - Pool statistics
    """

    def __init__(self, network_cidr: Optional[str] = None):
        """
        Initialize IPAM with network CIDR

        Args:
            network_cidr: Network in CIDR notation (e.g., "10.0.0.0/24")
        """
        self.network_cidr = network_cidr or settings.OVERLAY_NETWORK
        self.network = ipaddress.IPv4Network(self.network_cidr, strict=False)
        self.gateway = settings.OVERLAY_GATEWAY

        # Reserved IPs that cannot be allocated
        self._reserved_ips = self._calculate_reserved_ips()

        logger.info(f"IPAM initialized with network {self.network_cidr}")

    def _calculate_reserved_ips(self) -> set:
        """Calculate reserved IP addresses"""
        reserved = {
            str(self.network.network_address),      # Network address (10.0.0.0)
            str(self.network.broadcast_address),    # Broadcast (10.0.0.255)
            self.gateway,                            # Gateway/Hub (10.0.0.1)
        }
        return reserved

    @property
    def prefix_length(self) -> int:
        """Get network prefix length"""
        return self.network.prefixlen

    @property
    def total_hosts(self) -> int:
        """Total allocatable host addresses"""
        return self.network.num_addresses - len(self._reserved_ips) - 2

    def is_reserved(self, ip: str) -> bool:
        """Check if IP is reserved"""
        return ip in self._reserved_ips

    def allocate_ip(self, db: Session, node_id: Optional[int] = None) -> str:
        """
        Allocate next available IP from the pool

        Args:
            db: Database session
            node_id: Optional node ID to associate with allocation

        Returns:
            IP address without CIDR (e.g., "10.0.0.2")

        Raises:
            RuntimeError: If IP pool is exhausted
        """
        # Get all used IPs from nodes table
        used_ips = set()
        nodes = db.query(Node).filter(Node.overlay_ip.isnot(None)).all()
        for node in nodes:
            # Extract IP without CIDR
            ip = node.overlay_ip.split('/')[0] if '/' in str(node.overlay_ip) else node.overlay_ip
            used_ips.add(ip)

        # Find first available IP
        for ip in self.network.hosts():
            ip_str = str(ip)
            if ip_str not in used_ips and not self.is_reserved(ip_str):
                logger.info(f"Allocated IP {ip_str} for node_id={node_id}")
                return ip_str

        logger.error("IP pool exhausted!")
        raise RuntimeError("IP pool exhausted. No available addresses.")

    def allocate_ip_with_cidr(self, db: Session, node_id: Optional[int] = None) -> str:
        """
        Allocate IP with CIDR notation

        Returns:
            IP address with CIDR (e.g., "10.0.0.2/24")
        """
        ip = self.allocate_ip(db, node_id)
        return f"{ip}/{self.prefix_length}"

    def release_ip(self, db: Session, overlay_ip: str) -> bool:
        """
        Release an IP back to the pool

        Note: IPs are released automatically when node is deleted.
        This is mainly for tracking in IPAllocation table.
        """
        ip = overlay_ip.split('/')[0] if '/' in overlay_ip else overlay_ip

        allocation = db.query(IPAllocation).filter(
            IPAllocation.ip_address == ip
        ).first()

        if allocation:
            allocation.node_id = None
            allocation.released_at = datetime.utcnow()
            db.commit()
            logger.info(f"Released IP {ip}")
            return True

        return False

    def get_allocation_stats(self, db: Session) -> dict:
        """
        Get IP allocation statistics

        Returns:
            Dictionary with allocation stats
        """
        nodes = db.query(Node).filter(Node.overlay_ip.isnot(None)).all()
        used_count = len(nodes)

        return {
            "network": self.network_cidr,
            "gateway": self.gateway,
            "total_hosts": self.total_hosts,
            "used": used_count,
            "available": self.total_hosts - used_count,
            "reserved": list(self._reserved_ips),
            "utilization_percent": round((used_count / self.total_hosts) * 100, 2) if self.total_hosts > 0 else 0
        }

    def get_used_ips(self, db: Session) -> List[Tuple[str, str]]:
        """
        Get list of used IPs with their hostnames

        Returns:
            List of (ip, hostname) tuples
        """
        nodes = db.query(Node).filter(Node.overlay_ip.isnot(None)).all()
        return [(node.overlay_ip, node.hostname) for node in nodes]

    def validate_ip(self, ip: str) -> Tuple[bool, str]:
        """
        Validate if an IP belongs to the overlay network

        Returns:
            Tuple of (is_valid, message)
        """
        try:
            # Remove CIDR if present
            ip_only = ip.split('/')[0] if '/' in ip else ip
            ip_obj = ipaddress.IPv4Address(ip_only)

            if ip_obj not in self.network:
                return False, f"IP {ip} is not in network {self.network_cidr}"

            if self.is_reserved(ip_only):
                return False, f"IP {ip} is reserved"

            return True, "Valid"

        except ipaddress.AddressValueError as e:
            return False, f"Invalid IP format: {e}"


# Singleton instance
ipam_service = IPAMService()


# Legacy function for backward compatibility
def allocate_ip(db: Session) -> str:
    """Legacy function - use ipam_service.allocate_ip() instead"""
    return ipam_service.allocate_ip(db)