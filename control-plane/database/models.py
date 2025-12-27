# control-plane/database/models.py
"""
SQLAlchemy Database Models for Zero Trust Control Plane
"""

from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, Text,
    Index, Float
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

    # Trust Score (Dynamic Trust Algorithm)
    trust_score = Column(Float, default=1.0, nullable=False,
                         comment="Trust score 0.0-1.0, lower = less trusted")
    trust_factors = Column(Text, nullable=True,
                           comment="JSON-encoded trust factor breakdown")
    last_trust_update = Column(DateTime, nullable=True,
                               comment="Last trust score recalculation")
    risk_level = Column(String(20), default="low", nullable=False,
                        comment="Risk level: low, medium, high, critical")

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


class NodeHistory(Base):
    """
    Node History table - tracks node lifecycle events
    Stores detailed history of node status changes, installations, uninstalls

    Use cases:
    - Track when node was installed/uninstalled
    - Monitor node uptime patterns
    - Audit trail for compliance
    - Debug connectivity issues
    """
    __tablename__ = "node_history"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Node reference
    node_id = Column(Integer, nullable=False, index=True,
                     comment="Reference to nodes.id")
    hostname = Column(String(63), nullable=False, index=True,
                      comment="Hostname at time of event (denormalized for history)")

    # Event information
    event = Column(String(50), nullable=False, index=True,
                   comment="Event: registered, re-registered, uninstalled, status_changed, heartbeat_lost, peer_added, peer_removed")

    # Status tracking
    old_status = Column(String(20), nullable=True,
                        comment="Previous status (for status_changed events)")
    new_status = Column(String(20), nullable=True,
                        comment="New status (for status_changed events)")

    # Network state at event time
    overlay_ip = Column(String(18), nullable=True,
                        comment="Overlay IP at time of event")
    real_ip = Column(String(45), nullable=True,
                     comment="Public IP at time of event")
    public_key = Column(String(44), nullable=True,
                        comment="WireGuard public key at time of event")

    # Additional context
    details = Column(Text, nullable=True,
                     comment="JSON-encoded additional details")
    triggered_by = Column(String(50), nullable=True,
                          comment="What triggered: agent, admin, system, hub")

    # Timestamp
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Indexes for common queries
    __table_args__ = (
        Index('ix_node_history_node_event', 'node_id', 'event'),
        Index('ix_node_history_event_created', 'event', 'created_at'),
        Index('ix_node_history_hostname_created', 'hostname', 'created_at'),
    )


class TrustHistory(Base):
    """
    Trust History table - tracks trust score changes over time
    Used for trend analysis and anomaly detection
    """
    __tablename__ = "trust_history"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Node reference
    node_id = Column(Integer, nullable=False, index=True,
                     comment="Reference to nodes.id")
    hostname = Column(String(63), nullable=False,
                      comment="Hostname for quick reference")

    # Trust metrics
    trust_score = Column(Float, nullable=False,
                         comment="Trust score at this point in time")
    previous_score = Column(Float, nullable=True,
                            comment="Previous trust score for delta calculation")

    # Risk assessment
    risk_level = Column(String(20), nullable=False,
                        comment="Risk level: low, medium, high, critical")
    risk_factors = Column(Text, nullable=True,
                          comment="JSON array of risk factors detected")

    # Factor breakdown (for analysis)
    device_health_score = Column(Float, nullable=True,
                                 comment="CPU/Memory/Disk health component")
    security_score = Column(Float, nullable=True,
                            comment="Security events component")
    behavior_score = Column(Float, nullable=True,
                            comment="Behavioral analysis component")
    role_score = Column(Float, nullable=True,
                        comment="Role-based base score")

    # Raw metrics snapshot
    metrics_snapshot = Column(Text, nullable=True,
                              comment="JSON snapshot of raw metrics at calculation time")

    # Action taken (if any)
    action_taken = Column(String(50), nullable=True,
                          comment="Action: none, warning, rate_limit, suspend, revoke")

    # Timestamp
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Indexes
    __table_args__ = (
        Index('ix_trust_history_node_created', 'node_id', 'created_at'),
        Index('ix_trust_history_score', 'trust_score'),
        Index('ix_trust_history_risk', 'risk_level', 'created_at'),
    )