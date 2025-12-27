# control-plane/schemas/config.py
"""
Configuration schemas for Agent
"""

from pydantic import BaseModel, Field, ConfigDict
from typing import Optional, List
from datetime import datetime

from .policy import FirewallRule


class PeerConfig(BaseModel):
    """WireGuard peer configuration"""
    public_key: str = Field(..., description="Peer's WireGuard public key")
    allowed_ips: str = Field(..., description="Allowed IP ranges for this peer", examples=["10.0.0.2/32"])
    endpoint: Optional[str] = Field(None, description="Peer endpoint (IP:Port)", examples=["203.0.113.10:51820"])
    persistent_keepalive: int = Field(default=25, description="Keepalive interval in seconds")

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "public_key": "xYz123AbC456DeF789GhI012JkL345MnO678PqR901=",
                "allowed_ips": "10.0.0.2/32",
                "endpoint": "203.0.113.10:51820",
                "persistent_keepalive": 25
            }
        }
    )


class InterfaceConfig(BaseModel):
    """WireGuard interface configuration"""
    address: str = Field(..., description="Interface IP address with CIDR", examples=["10.0.0.2/24"])
    private_key_path: str = Field(
        default="/etc/wireguard/private.key",
        description="Path to private key file"
    )
    listen_port: Optional[int] = Field(None, ge=1, le=65535, description="Listen port (optional for clients)")
    dns: List[str] = Field(default=["10.0.0.1"], description="DNS servers")
    mtu: int = Field(default=1420, description="Interface MTU")

    # Post up/down scripts
    post_up: Optional[str] = Field(None, description="Command to run after interface up")
    post_down: Optional[str] = Field(None, description="Command to run after interface down")

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "address": "10.0.0.2/24",
                "private_key_path": "/etc/wireguard/private.key",
                "listen_port": None,
                "dns": ["10.0.0.1", "1.1.1.1"],
                "mtu": 1420,
                "post_up": "/opt/zt-agent/scripts/apply-acl.sh",
                "post_down": "/opt/zt-agent/scripts/remove-acl.sh"
            }
        }
    )


class WireGuardConfig(BaseModel):
    """
    Complete WireGuard configuration for Agent
    Used to generate wg0.conf
    """
    interface: InterfaceConfig
    peers: List[PeerConfig]

    # Metadata
    config_version: int = Field(..., description="Config version for change detection")
    generated_at: datetime = Field(default_factory=datetime.utcnow)

    model_config = ConfigDict(from_attributes=True)


class AgentConfig(BaseModel):
    """
    Complete configuration for Zero Trust Agent
    Includes WireGuard config and ACL rules
    """
    # Node identification
    node_id: int
    hostname: str
    role: str
    status: str

    # Network config
    overlay_ip: str = Field(..., description="Assigned overlay IP", examples=["10.0.0.2/24"])

    # Hub connection
    hub_public_key: str
    hub_endpoint: str = Field(..., examples=["hub.example.com:51820"])

    # WireGuard peers (for mesh topology)
    peers: List[PeerConfig] = Field(default_factory=list)

    # Zero Trust ACL rules
    acl_rules: List[FirewallRule] = Field(default_factory=list)

    # Metadata
    config_version: int = Field(default=1)
    generated_at: datetime = Field(default_factory=datetime.utcnow)
    next_sync_seconds: int = Field(default=60, description="Recommended sync interval")

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "example": {
                "node_id": 1,
                "hostname": "odoo-prod-01",
                "role": "app",
                "status": "active",
                "overlay_ip": "10.0.0.2/24",
                "hub_public_key": "xYz123AbC456DeF789GhI012JkL345MnO678PqR901=",
                "hub_endpoint": "hub.example.com:51820",
                "peers": [],
                "acl_rules": [
                    {"src_ip": "10.0.0.3", "port": 22, "proto": "tcp", "action": "ACCEPT"}
                ],
                "config_version": 1,
                "generated_at": "2025-12-26T10:00:00Z",
                "next_sync_seconds": 60
            }
        }
    )


class HeartbeatRequest(BaseModel):
    """Heartbeat request from Agent with security metrics"""
    hostname: str
    public_key: str
    agent_version: Optional[str] = None
    uptime_seconds: Optional[int] = None

    # Resource metrics
    cpu_percent: Optional[float] = None
    memory_percent: Optional[float] = None
    disk_percent: Optional[float] = None

    # Security and network metrics for trust calculation
    security_events: Optional[dict] = Field(
        None,
        description="Security events collected by agent"
    )
    network_stats: Optional[dict] = Field(
        None,
        description="Network connection statistics"
    )

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "hostname": "odoo-prod-01",
                "public_key": "aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9dE=",
                "agent_version": "1.0.0",
                "uptime_seconds": 86400,
                "cpu_percent": 25.5,
                "memory_percent": 60.0,
                "disk_percent": 45.0,
                "security_events": {
                    "summary": {
                        "risk_level": "low",
                        "risk_factors": []
                    }
                },
                "network_stats": {
                    "connections": {"total": 50}
                }
            }
        }
    )


class HeartbeatResponse(BaseModel):
    """Heartbeat response to Agent with trust information"""
    status: str = "ok"
    config_changed: bool = False
    current_config_version: int
    server_time: datetime = Field(default_factory=datetime.utcnow)
    message: Optional[str] = None

    # Trust information
    trust_score: Optional[float] = Field(
        None,
        ge=0.0, le=1.0,
        description="Current trust score (0-1)"
    )
    risk_level: Optional[str] = Field(
        None,
        description="Current risk level"
    )
    action_taken: Optional[str] = Field(
        None,
        description="Action taken based on trust score"
    )
