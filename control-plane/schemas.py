# control-plane/schemas.py
"""
Legacy schemas module - redirects to new schemas package
This file exists for backward compatibility only.
New code should import from schemas package directly.
"""

# Re-export from new schemas package
from schemas.node import (
    NodeCreate,
    NodeResponse,
    NodeUpdate,
    NodeRole,
    NodeStatus,
    NodeRegistrationResponse,
    NodeListResponse,
)

from schemas.policy import (
    PolicyCreate,
    PolicyUpdate,
    PolicyResponse,
    PolicyListResponse,
    FirewallRule,
    Protocol,
    Action,
)

from schemas.config import (
    PeerConfig,
    InterfaceConfig,
    WireGuardConfig,
    AgentConfig,
    HeartbeatRequest,
    HeartbeatResponse,
)

from schemas.base import (
    BaseResponse,
    ErrorResponse,
    PaginatedResponse,
    HealthResponse,
)

__all__ = [
    # Node
    "NodeCreate",
    "NodeResponse",
    "NodeUpdate",
    "NodeRole",
    "NodeStatus",
    "NodeRegistrationResponse",
    "NodeListResponse",
    # Policy
    "PolicyCreate",
    "PolicyUpdate",
    "PolicyResponse",
    "PolicyListResponse",
    "FirewallRule",
    "Protocol",
    "Action",
    # Config
    "PeerConfig",
    "InterfaceConfig",
    "WireGuardConfig",
    "AgentConfig",
    "HeartbeatRequest",
    "HeartbeatResponse",
    # Base
    "BaseResponse",
    "ErrorResponse",
    "PaginatedResponse",
    "HealthResponse",
]