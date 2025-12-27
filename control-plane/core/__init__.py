# control-plane/core/__init__.py
"""
Core business logic modules
"""

from .ipam import ipam_service, allocate_ip, IPAMService
from .policy_engine import policy_engine, generate_acl, build_config_for_node, PolicyEngine
from .node_manager import (
    node_manager,
    register_node,
    get_next_ip,
    NodeManager,
    NETWORK_CIDR,
    SERVER_IP,
    SERVER_PUBLIC_KEY,
    SERVER_ENDPOINT
)
from .trust_engine import trust_engine, TrustEngine
from .wireguard_service import wireguard_service

__all__ = [
    # IPAM
    "ipam_service",
    "allocate_ip",
    "IPAMService",
    # Policy Engine
    "policy_engine",
    "generate_acl",
    "build_config_for_node",
    "PolicyEngine",
    # Node Manager
    "node_manager",
    "register_node",
    "get_next_ip",
    "NodeManager",
    "NETWORK_CIDR",
    "SERVER_IP",
    "SERVER_PUBLIC_KEY",
    "SERVER_ENDPOINT",
    # Trust Engine
    "trust_engine",
    "TrustEngine",
    # WireGuard Service
    "wireguard_service",
]
