# control-plane/schemas/policy.py
"""
Policy-related Pydantic schemas
"""

from pydantic import BaseModel, Field, field_validator, ConfigDict
from typing import Optional, List
from datetime import datetime
from enum import Enum


class Protocol(str, Enum):
    """Supported network protocols"""
    TCP = "tcp"
    UDP = "udp"
    ICMP = "icmp"
    ANY = "any"


class Action(str, Enum):
    """Firewall rule actions"""
    ACCEPT = "ACCEPT"
    DROP = "DROP"
    REJECT = "REJECT"
    LOG = "LOG"


# === Request Schemas ===

class PolicyCreate(BaseModel):
    """Schema for creating a new access policy"""
    name: str = Field(
        ...,
        min_length=3,
        max_length=100,
        description="Human-readable policy name",
        examples=["allow-app-to-db"]
    )
    description: Optional[str] = Field(
        None,
        max_length=255
    )
    src_role: str = Field(
        ...,
        description="Source role (who initiates the connection)",
        examples=["app", "ops", "*"]
    )
    dst_role: str = Field(
        ...,
        description="Destination role (who receives the connection)",
        examples=["db", "app", "*"]
    )
    port: int = Field(
        ...,
        ge=1,
        le=65535,
        description="Destination port",
        examples=[5432, 22, 443]
    )
    protocol: Protocol = Field(
        default=Protocol.TCP,
        description="Network protocol"
    )
    action: Action = Field(
        default=Action.ACCEPT,
        description="Action to take when rule matches"
    )
    priority: int = Field(
        default=100,
        ge=1,
        le=1000,
        description="Rule priority (lower = higher priority)"
    )
    enabled: bool = Field(
        default=True,
        description="Whether the policy is active"
    )

    @field_validator('src_role', 'dst_role')
    @classmethod
    def validate_role(cls, v: str) -> str:
        """Validate role format"""
        v = v.lower().strip()
        valid_roles = ['hub', 'app', 'db', 'ops', 'monitor', 'gateway', '*']
        if v not in valid_roles:
            raise ValueError(f'Invalid role. Must be one of: {", ".join(valid_roles)}')
        return v

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "name": "allow-app-to-db",
                "description": "Allow application servers to connect to database",
                "src_role": "app",
                "dst_role": "db",
                "port": 5432,
                "protocol": "tcp",
                "action": "ACCEPT",
                "priority": 100,
                "enabled": True
            }
        }
    )


class PolicyUpdate(BaseModel):
    """Schema for updating an existing policy"""
    name: Optional[str] = Field(None, min_length=3, max_length=100)
    description: Optional[str] = Field(None, max_length=255)
    port: Optional[int] = Field(None, ge=1, le=65535)
    protocol: Optional[Protocol] = None
    action: Optional[Action] = None
    priority: Optional[int] = Field(None, ge=1, le=1000)
    enabled: Optional[bool] = None


# === Response Schemas ===

class PolicyResponse(BaseModel):
    """Standard policy response"""
    id: int
    name: str
    description: Optional[str] = None
    src_role: str
    dst_role: str
    port: int
    protocol: str
    action: str
    priority: int
    enabled: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PolicyListResponse(BaseModel):
    """Response for listing multiple policies"""
    policies: List[PolicyResponse]
    total: int

    model_config = ConfigDict(from_attributes=True)


# === Firewall Rule (compiled from policy) ===

class FirewallRule(BaseModel):
    """
    Compiled firewall rule for Agent
    Generated from policies by the Policy Engine
    """
    src_ip: str = Field(..., description="Source IP address", examples=["10.0.0.2"])
    dst_port: int = Field(..., alias="port", ge=1, le=65535)
    protocol: str = Field(default="tcp", alias="proto")
    action: str = Field(default="ACCEPT")
    comment: Optional[str] = Field(None, description="Rule description for logging")

    model_config = ConfigDict(
        populate_by_name=True,
        json_schema_extra={
            "example": {
                "src_ip": "10.0.0.2",
                "port": 5432,
                "proto": "tcp",
                "action": "ACCEPT",
                "comment": "Allow app to db"
            }
        }
    )
