# control-plane/schemas/__init__.py
"""
Pydantic Schemas for Zero Trust Control Plane API
Organized by domain: nodes, policies, config
"""

from .base import BaseResponse, ErrorResponse, PaginatedResponse
from .node import (
    NodeRole,
    NodeStatus,
    NodeCreate,
    NodeUpdate,
    NodeResponse,
    NodeListResponse,
)
from .policy import (
    PolicyCreate,
    PolicyUpdate,
    PolicyResponse,
    FirewallRule,
)
from .config import (
    PeerConfig,
    InterfaceConfig,
    WireGuardConfig,
    AgentConfig,
)

__all__ = [
    # Base
    "BaseResponse",
    "ErrorResponse",
    "PaginatedResponse",
    # Node
    "NodeRole",
    "NodeStatus",
    "NodeCreate",
    "NodeUpdate",
    "NodeResponse",
    "NodeListResponse",
    # Policy
    "PolicyCreate",
    "PolicyUpdate",
    "PolicyResponse",
    "FirewallRule",
    # Config
    "PeerConfig",
    "InterfaceConfig",
    "WireGuardConfig",
    "AgentConfig",
]
