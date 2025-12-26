# control-plane/database/models.py
"""
SQLAlchemy Database Models for Zero Trust Control Plane
"""

from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, Text,
    Index
)
from sqlalchemy.orm import declarative_base
from datetime import datetime
import enum

Base = declarative_base()


class NodeStatus(str, enum.Enum):
    """Node lifecycle status"""
    PENDING = "pending"
    ACTIVE = "active"
    SUSPENDED = "suspended"
    REVOKED = "revoked"


class NodeRole(str, enum.Enum):
    """Available node roles"""
    HUB = "hub"
    APP = "app"
    DB = "db"
    OPS = "ops"
    MONITOR = "monitor"
    GATEWAY = "gateway"


class Node(Base):
    """
    Node table - stores information about all nodes in the Zero Trust network
    Each VPS/Agent registers as a Node
    """
    __tablename__ = "nodes"

    # Primary Key
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Identity
    hostname = Column(String(63), unique=True, nullable=False, index=True,
                      comment="Unique hostname (RFC 1123 compliant)")
    role = Column(String(20), nullable=False, index=True,
                  comment="Node role: hub, app, db, ops, monitor, gateway")
    description = Column(Text, nullable=True,
                         comment="Optional description")

    # WireGuard Keys
    public_key = Column(String(44), unique=True, nullable=False,
                        comment="WireGuard public key (Base64)")
    preshared_key = Column(String(44), nullable=True,
                           comment="Optional PSK for additional security")

    # Network
    overlay_ip = Column(String(18), unique=True, nullable=True,
                        comment="Overlay network IP (e.g., 10.0.0.2/24)")
    real_ip = Column(String(45), nullable=True,
                     comment="Current public IP (updated on heartbeat)")
    listen_port = Column(Integer, default=51820,
                         comment="WireGuard listen port")

    # Status
    status = Column(String(20), default=NodeStatus.PENDING.value, nullable=False, index=True,
                    comment="Node status: pending, active, suspended, revoked")
    is_approved = Column(Boolean, default=False, nullable=False,
                         comment="Legacy: use status instead")

    # Agent Metadata
    agent_version = Column(String(20), nullable=True)
    os_info = Column(String(100), nullable=True)

    # Config versioning
    config_version = Column(Integer, default=1, nullable=False,
                            comment="Incremented when config changes")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    last_seen = Column(DateTime, nullable=True,
                       comment="Last heartbeat timestamp")

    # Indexes for common queries
    __table_args__ = (
        Index('ix_nodes_role_status', 'role', 'status'),
        Index('ix_nodes_status_last_seen', 'status', 'last_seen'),
    )

    def __repr__(self):
        return f"<Node(id={self.id}, hostname={self.hostname}, role={self.role}, status={self.status})>"

    @property
    def is_active(self) -> bool:
        """Check if node is active"""
        return self.status == NodeStatus.ACTIVE.value


class AccessPolicy(Base):
    """
    Access Policy table - defines who can access what
    Implements Zero Trust principle: explicit allow, default deny
    """
    __tablename__ = "policies"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Policy identification
    name = Column(String(100), unique=True, nullable=False,
                  comment="Human-readable policy name")
    description = Column(Text, nullable=True)

    # Access control
    src_role = Column(String(20), nullable=False, index=True,
                      comment="Source role (who initiates)")
    dst_role = Column(String(20), nullable=False, index=True,
                      comment="Destination role (who receives)")
    port = Column(Integer, nullable=False,
                  comment="Destination port (1-65535)")
    protocol = Column(String(10), default="tcp", nullable=False,
                      comment="Protocol: tcp, udp, icmp, any")
    action = Column(String(10), default="ACCEPT", nullable=False,
                    comment="Action: ACCEPT, DROP, REJECT, LOG")

    # Priority and state
    priority = Column(Integer, default=100, nullable=False,
                      comment="Rule priority (1-1000, lower = higher priority)")
    enabled = Column(Boolean, default=True, nullable=False,
                     comment="Whether policy is active")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    # Indexes
    __table_args__ = (
        Index('ix_policies_src_dst', 'src_role', 'dst_role'),
        Index('ix_policies_enabled_priority', 'enabled', 'priority'),
    )


class IPAllocation(Base):
    """
    IP Allocation table - tracks IP address assignments
    Separates IP management for easier pool expansion
    """
    __tablename__ = "ip_allocations"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Network information
    network_cidr = Column(String(18), nullable=False,
                          comment="Network CIDR (e.g., 10.0.0.0/24)")
    ip_address = Column(String(15), unique=True, nullable=False, index=True,
                        comment="IP address without CIDR")

    # Allocation status
    node_id = Column(Integer, nullable=True, index=True,
                     comment="Allocated to node ID (NULL = available)")

    # Timestamps
    allocated_at = Column(DateTime, nullable=True)
    released_at = Column(DateTime, nullable=True)

    # Index for finding free IPs
    __table_args__ = (
        Index('ix_ip_network_node', 'network_cidr', 'node_id'),
    )


class AuditLog(Base):
    """
    Audit Log table - records all security-relevant events
    Implements NIST SP 800-207 requirement for continuous monitoring
    """
    __tablename__ = "audit_logs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Event information
    event_type = Column(String(50), nullable=False, index=True,
                        comment="Event type: registration, approval, config_sync, etc.")
    event_action = Column(String(20), nullable=False,
                          comment="Action: create, update, delete, access")

    # Actor
    actor_type = Column(String(20), nullable=False,
                        comment="Who performed: node, admin, system")
    actor_id = Column(String(100), nullable=True,
                      comment="Actor identifier (node hostname, admin username)")
    actor_ip = Column(String(45), nullable=True,
                      comment="Actor IP address")

    # Target
    target_type = Column(String(50), nullable=True,
                         comment="Target resource type")
    target_id = Column(String(100), nullable=True,
                       comment="Target resource identifier")

    # Details
    details = Column(Text, nullable=True,
                     comment="JSON-encoded additional details")
    status = Column(String(20), default="success", nullable=False,
                    comment="Outcome: success, failure, denied")

    # Timestamp
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Indexes for querying
    __table_args__ = (
        Index('ix_audit_event_created', 'event_type', 'created_at'),
        Index('ix_audit_actor_created', 'actor_type', 'actor_id', 'created_at'),
    )