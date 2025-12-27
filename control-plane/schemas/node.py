# control-plane/schemas/node.py
"""
Node-related Pydantic schemas
"""

from pydantic import BaseModel, Field, field_validator, ConfigDict
from typing import Optional, List
from datetime import datetime
from enum import Enum
import re


class NodeRole(str, Enum):
    """Available node roles in the Zero Trust network"""
    HUB = "hub"          # Control Plane / WireGuard Server
    APP = "app"          # Application servers (Odoo, Web...)
    DB = "db"            # Database servers (PostgreSQL...)
    OPS = "ops"          # Operations / Admin access
    MONITOR = "monitor"  # Monitoring systems
    GATEWAY = "gateway"  # Edge gateway
    CLIENT = "client"    # End-user devices (mobile, laptop)


class NodeStatus(str, Enum):
    """Node lifecycle status"""
    PENDING = "pending"      # Waiting for approval
    ACTIVE = "active"        # Active and approved
    SUSPENDED = "suspended"  # Temporarily suspended
    REVOKED = "revoked"      # Permanently revoked


class DeviceType(str, Enum):
    """Client device types for mobile/laptop VPN access"""
    MOBILE = "mobile"        # iOS, Android phones/tablets
    LAPTOP = "laptop"        # Windows, macOS, Linux laptops
    DESKTOP = "desktop"      # Desktop computers
    OTHER = "other"          # Other devices


class TunnelMode(str, Enum):
    """VPN tunnel mode for client devices"""
    FULL = "full"            # Route all traffic through VPN (0.0.0.0/0)
    SPLIT = "split"          # Only route overlay network traffic


# === Request Schemas ===

class NodeCreate(BaseModel):
    """
    Schema for registering a new node
    Agent sends this data during initial bootstrap
    """
    hostname: str = Field(
        ...,
        min_length=3,
        max_length=63,
        description="Unique hostname for the node",
        examples=["odoo-prod-01", "postgres-primary"]
    )
    role: NodeRole = Field(
        ...,
        description="Role of the node in the network",
        examples=["app", "db"]
    )
    public_key: str = Field(
        ...,
        min_length=44,
        max_length=44,
        description="WireGuard public key (Base64 encoded)",
        examples=["aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9dE="]
    )
    description: Optional[str] = Field(
        None,
        max_length=255,
        description="Optional description of the node"
    )
    agent_version: Optional[str] = Field(
        None,
        max_length=20,
        examples=["1.0.0"]
    )
    os_info: Optional[str] = Field(
        None,
        max_length=100,
        examples=["Ubuntu 22.04 LTS"]
    )

    @field_validator('public_key')
    @classmethod
    def validate_wireguard_key(cls, v: str) -> str:
        """Validate WireGuard public key format (Base64, 44 chars ending with =)"""
        if not re.match(r'^[A-Za-z0-9+/]{43}=$', v):
            raise ValueError('Invalid WireGuard public key format. Must be 44 chars Base64 ending with =')
        return v

    @field_validator('hostname')
    @classmethod
    def validate_hostname(cls, v: str) -> str:
        """
        Validate hostname format (RFC 1123)
        - Lowercase alphanumeric with hyphens
        - Cannot start or end with hyphen
        """
        v = v.lower().strip()
        if not re.match(r'^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$', v):
            raise ValueError(
                'Hostname must be lowercase alphanumeric with optional hyphens, '
                'cannot start/end with hyphen, max 63 chars'
            )
        return v

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "hostname": "odoo-prod-01",
                "role": "app",
                "public_key": "aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9dE=",
                "description": "Production Odoo server",
                "agent_version": "1.0.0",
                "os_info": "Ubuntu 22.04 LTS"
            }
        }
    )


class NodeUpdate(BaseModel):
    """Schema for updating node information"""
    description: Optional[str] = Field(None, max_length=255)
    status: Optional[NodeStatus] = None
    role: Optional[NodeRole] = None

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "description": "Updated description",
                "status": "active"
            }
        }
    )


# === Response Schemas ===

class NodeResponse(BaseModel):
    """
    Standard node response
    Used for single node operations
    """
    id: int
    hostname: str
    role: NodeRole
    status: NodeStatus
    overlay_ip: Optional[str] = None
    real_ip: Optional[str] = None
    public_key: str
    description: Optional[str] = None
    agent_version: Optional[str] = None
    os_info: Optional[str] = None
    last_seen: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "id": 1,
                "hostname": "odoo-prod-01",
                "role": "app",
                "status": "active",
                "overlay_ip": "10.0.0.2",
                "real_ip": "203.0.113.10",
                "public_key": "aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9dE=",
                "description": "Production Odoo server",
                "agent_version": "1.0.0",
                "os_info": "Ubuntu 22.04 LTS",
                "last_seen": "2025-12-26T10:00:00Z",
                "created_at": "2025-12-26T08:00:00Z",
                "updated_at": "2025-12-26T10:00:00Z"
            }
        }
    )


class NodeRegistrationResponse(BaseModel):
    """
    Response after successful node registration
    Contains WireGuard configuration for the agent
    """
    node_id: int
    hostname: str
    status: NodeStatus
    overlay_ip: str = Field(..., description="Assigned overlay IP with CIDR", examples=["10.0.0.2/24"])

    # Hub connection info
    hub_public_key: str
    hub_endpoint: str = Field(..., examples=["hub.example.com:51820"])

    # Network config
    dns_servers: List[str] = Field(default=["10.0.0.1"])
    allowed_ips: str = Field(default="10.0.0.0/24")

    message: str = "Registration successful"

    model_config = ConfigDict(from_attributes=True)


class NodeListResponse(BaseModel):
    """Response for listing multiple nodes"""
    nodes: List[NodeResponse]
    total: int

    model_config = ConfigDict(from_attributes=True)


# === Client Device Schemas (Mobile/Laptop VPN Access) ===

class ClientDeviceCreate(BaseModel):
    """
    Schema for registering a new client device (mobile/laptop)
    Admin or user creates this to get WireGuard config
    """
    device_name: str = Field(
        ...,
        min_length=2,
        max_length=64,
        description="User-friendly device name",
        examples=["iPhone-John", "MacBook-Pro-Work"]
    )
    device_type: DeviceType = Field(
        default=DeviceType.MOBILE,
        description="Type of device"
    )
    user_id: Optional[str] = Field(
        None,
        max_length=100,
        description="Owner user ID (for multi-user support)",
        examples=["john.doe@company.com"]
    )
    tunnel_mode: TunnelMode = Field(
        default=TunnelMode.FULL,
        description="VPN tunnel mode: full (all traffic) or split (overlay only)"
    )
    expires_days: int = Field(
        default=30,
        ge=1,
        le=365,
        description="Config expiration in days"
    )
    description: Optional[str] = Field(
        None,
        max_length=255,
        description="Optional description"
    )

    @field_validator('device_name')
    @classmethod
    def validate_device_name(cls, v: str) -> str:
        """Validate device name - alphanumeric with hyphens/underscores"""
        v = v.strip()
        if not re.match(r'^[a-zA-Z0-9][a-zA-Z0-9\-_\s]{0,62}[a-zA-Z0-9]$|^[a-zA-Z0-9]$', v):
            raise ValueError(
                'Device name must be alphanumeric with optional hyphens, underscores, spaces'
            )
        return v

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "device_name": "iPhone-John",
                "device_type": "mobile",
                "user_id": "john.doe@company.com",
                "tunnel_mode": "full",
                "expires_days": 30,
                "description": "John's work iPhone"
            }
        }
    )


class ClientDeviceResponse(BaseModel):
    """Response after client device registration"""
    id: int
    device_name: str
    device_type: DeviceType
    user_id: Optional[str] = None
    tunnel_mode: TunnelMode
    status: NodeStatus
    overlay_ip: str
    public_key: str
    created_at: datetime
    expires_at: datetime

    # Config download info
    config_token: str = Field(..., description="One-time token to download config")

    model_config = ConfigDict(from_attributes=True)


class ClientConfigResponse(BaseModel):
    """
    Complete WireGuard config for client device
    Can be displayed as text or QR code
    """
    device_name: str
    device_type: DeviceType
    tunnel_mode: TunnelMode

    # WireGuard config (ready to save as .conf file)
    wireguard_config: str = Field(..., description="Complete wg0.conf content")

    # QR code for mobile apps
    qr_code_base64: Optional[str] = Field(None, description="Base64 encoded QR code PNG image")

    # Metadata
    overlay_ip: str
    expires_at: datetime
    hub_endpoint: str

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "device_name": "iPhone-John",
                "device_type": "mobile",
                "tunnel_mode": "full",
                "wireguard_config": "[Interface]\\nPrivateKey=...\\n[Peer]\\n...",
                "qr_code_base64": "iVBORw0KGgoAAAANSUhEU...",
                "overlay_ip": "10.0.0.50/24",
                "expires_at": "2026-01-26T00:00:00Z",
                "hub_endpoint": "hub.example.com:51820"
            }
        }
    )


class ClientDeviceListResponse(BaseModel):
    """Response for listing client devices"""
    devices: List[ClientDeviceResponse]
    total: int

    model_config = ConfigDict(from_attributes=True)
