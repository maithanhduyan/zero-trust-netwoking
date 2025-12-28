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
    CLIENT = "client"      # End-user devices (mobile, laptop)


class DeviceType(str, enum.Enum):
    """Client device types"""
    MOBILE = "mobile"
    LAPTOP = "laptop"
    DESKTOP = "desktop"
    OTHER = "other"


class TunnelMode(str, enum.Enum):
    """VPN tunnel mode for client devices"""
    FULL = "full"          # Route all traffic (0.0.0.0/0)
    SPLIT = "split"        # Only overlay network


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


class ClientDevice(Base):
    """
    Client Device table - stores mobile/laptop devices for VPN access
    These are end-user devices that connect via WireGuard client app
    Unlike Nodes (servers with agents), these are lightweight consumers
    """
    __tablename__ = "client_devices"

    # Primary Key
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Device Identity
    device_name = Column(String(64), nullable=False,
                         comment="User-friendly device name")
    device_type = Column(String(20), default=DeviceType.MOBILE.value, nullable=False,
                         comment="Device type: mobile, laptop, desktop, other")
    user_id = Column(String(100), nullable=True, index=True,
                     comment="Owner user ID (email or username)")
    description = Column(Text, nullable=True,
                         comment="Optional description")

    # WireGuard Keys (generated server-side for clients)
    public_key = Column(String(44), unique=True, nullable=False,
                        comment="WireGuard public key (Base64)")
    private_key_encrypted = Column(Text, nullable=False,
                                   comment="Encrypted private key (for config generation)")
    preshared_key = Column(String(44), nullable=True,
                           comment="Optional PSK for additional security")

    # Network
    overlay_ip = Column(String(18), unique=True, nullable=False,
                        comment="Overlay network IP (e.g., 10.0.0.50/24)")
    tunnel_mode = Column(String(10), default=TunnelMode.FULL.value, nullable=False,
                         comment="Tunnel mode: full (0.0.0.0/0) or split (overlay only)")

    # Status
    status = Column(String(20), default=NodeStatus.ACTIVE.value, nullable=False, index=True,
                    comment="Device status: active, suspended, revoked")

    # Config token (one-time download)
    config_token = Column(String(64), unique=True, nullable=True,
                          comment="Token to download config (cleared after first use)")
    config_downloaded = Column(Boolean, default=False, nullable=False,
                               comment="Whether config has been downloaded")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=False,
                        comment="When this device config expires")
    last_seen = Column(DateTime, nullable=True,
                       comment="Last handshake timestamp (from WireGuard)")

    # Indexes
    __table_args__ = (
        Index('ix_client_devices_user', 'user_id'),
        Index('ix_client_devices_status_expires', 'status', 'expires_at'),
        Index('ix_client_devices_token', 'config_token'),
    )

    def __repr__(self):
        return f"<ClientDevice(id={self.id}, name={self.device_name}, user={self.user_id}, status={self.status})>"

    @property
    def is_active(self) -> bool:
        """Check if device is active and not expired"""
        if self.status != NodeStatus.ACTIVE.value:
            return False
        if self.expires_at and datetime.utcnow() > self.expires_at:
            return False
        return True

    @property
    def is_expired(self) -> bool:
        """Check if device config has expired"""
        return self.expires_at and datetime.utcnow() > self.expires_at


# =============================================================================
# Event Store - Persistent Event History
# =============================================================================

class EventStore(Base):
    """
    Event Store table - persistent storage for all domain events

    Enables:
    - Audit trail and compliance
    - Event replay for debugging
    - Analytics and monitoring
    - System state reconstruction
    """
    __tablename__ = "event_store"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Event identification
    event_id = Column(String(36), unique=True, nullable=False, index=True,
                      comment="UUID of the event")
    event_type = Column(String(50), nullable=False, index=True,
                        comment="Event type: NodeRegistered, PolicyUpdated, etc.")

    # Aggregate information (for event sourcing)
    aggregate_type = Column(String(50), nullable=True, index=True,
                            comment="Aggregate type: Node, Policy, Client, etc.")
    aggregate_id = Column(String(100), nullable=True, index=True,
                          comment="ID of the aggregate this event belongs to")

    # Event data
    payload = Column(Text, nullable=False,
                     comment="JSON-encoded event payload")
    source = Column(String(50), nullable=True,
                    comment="Component that emitted the event")

    # Metadata
    version = Column(Integer, default=1, nullable=False,
                     comment="Event schema version for evolution")
    correlation_id = Column(String(36), nullable=True, index=True,
                            comment="ID to correlate related events")
    causation_id = Column(String(36), nullable=True,
                          comment="ID of the event that caused this one")

    # Processing status
    processed = Column(Boolean, default=False, nullable=False,
                       comment="Whether event has been processed by all handlers")
    process_count = Column(Integer, default=0, nullable=False,
                           comment="Number of handlers that processed this event")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Indexes for common queries
    __table_args__ = (
        Index('ix_event_store_type_created', 'event_type', 'created_at'),
        Index('ix_event_store_aggregate', 'aggregate_type', 'aggregate_id', 'created_at'),
        Index('ix_event_store_correlation', 'correlation_id'),
    )

    def __repr__(self):
        return f"<EventStore(id={self.id}, type={self.event_type}, aggregate={self.aggregate_type}/{self.aggregate_id})>"


# =============================================================================
# User & Group Access Control
# =============================================================================

class User(Base):
    """
    User table - represents individual users for access control

    Users can:
    - Own client devices (mobile/laptop VPN)
    - Belong to groups
    - Have individual access policies
    """
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Identity
    user_id = Column(String(100), unique=True, nullable=False, index=True,
                     comment="Unique user identifier (email or username)")
    display_name = Column(String(100), nullable=True,
                          comment="Human-readable display name")
    email = Column(String(255), unique=True, nullable=True, index=True,
                   comment="User email address")

    # Authentication (optional - can use external IdP)
    password_hash = Column(String(255), nullable=True,
                           comment="Hashed password (if using local auth)")
    external_id = Column(String(255), nullable=True, index=True,
                         comment="ID from external identity provider")
    auth_provider = Column(String(50), nullable=True,
                           comment="Auth provider: local, google, okta, etc.")

    # Status
    status = Column(String(20), default="active", nullable=False,
                    comment="User status: active, suspended, disabled")

    # Metadata
    department = Column(String(100), nullable=True,
                        comment="Department or team")
    job_title = Column(String(100), nullable=True,
                       comment="Job title/role in organization")
    attributes = Column(Text, nullable=True,
                        comment="JSON-encoded custom attributes")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    last_login = Column(DateTime, nullable=True,
                        comment="Last successful login")

    # Indexes
    __table_args__ = (
        Index('ix_users_status', 'status'),
        Index('ix_users_department', 'department'),
    )

    def __repr__(self):
        return f"<User(id={self.id}, user_id={self.user_id}, status={self.status})>"


class Group(Base):
    """
    Group table - represents user groups for access control

    Groups provide:
    - Organizational structure (teams, departments)
    - Shared access policies
    - Simplified permission management
    """
    __tablename__ = "groups"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Identity
    name = Column(String(100), unique=True, nullable=False, index=True,
                  comment="Unique group name")
    display_name = Column(String(100), nullable=True,
                          comment="Human-readable display name")
    description = Column(Text, nullable=True,
                         comment="Group description")

    # Hierarchy
    parent_group_id = Column(Integer, nullable=True, index=True,
                             comment="Parent group ID for nested groups")

    # Type
    group_type = Column(String(50), default="team", nullable=False,
                        comment="Group type: team, department, role, custom")

    # Status
    status = Column(String(20), default="active", nullable=False,
                    comment="Group status: active, disabled")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    def __repr__(self):
        return f"<Group(id={self.id}, name={self.name})>"


class UserGroupMembership(Base):
    """
    User-Group membership table - links users to groups
    """
    __tablename__ = "user_group_memberships"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    user_id = Column(Integer, nullable=False, index=True,
                     comment="Reference to users.id")
    group_id = Column(Integer, nullable=False, index=True,
                      comment="Reference to groups.id")

    # Role within group
    role = Column(String(50), default="member", nullable=False,
                  comment="Role in group: member, admin, owner")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Unique constraint
    __table_args__ = (
        Index('ix_user_group_unique', 'user_id', 'group_id', unique=True),
    )


class UserAccessPolicy(Base):
    """
    User Access Policy table - defines what resources users/groups can access

    Implements Zero Trust principle for user-level access:
    - Domain/URL access control
    - Zone/network segment access
    - Time-based access
    - Device restrictions
    """
    __tablename__ = "user_access_policies"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Policy identification
    name = Column(String(100), nullable=False,
                  comment="Policy name")
    description = Column(Text, nullable=True,
                         comment="Policy description")

    # Subject (who this policy applies to)
    subject_type = Column(String(20), nullable=False, index=True,
                          comment="Subject type: user, group, all")
    subject_id = Column(Integer, nullable=True, index=True,
                        comment="User or Group ID (NULL for 'all')")

    # Resource (what is being accessed)
    resource_type = Column(String(50), nullable=False, index=True,
                           comment="Resource type: domain, ip_range, zone, service")
    resource_value = Column(String(255), nullable=False,
                            comment="Resource value: *.example.com, 10.0.0.0/24, production, etc.")

    # Access control
    action = Column(String(20), default="allow", nullable=False,
                    comment="Action: allow, deny, require_mfa")

    # Conditions (optional)
    conditions = Column(Text, nullable=True,
                        comment="JSON-encoded conditions (time, device_type, location, etc.)")

    # Priority and state
    priority = Column(Integer, default=100, nullable=False,
                      comment="Rule priority (1-1000, lower = higher priority)")
    enabled = Column(Boolean, default=True, nullable=False,
                     comment="Whether policy is active")

    # Time-based access
    valid_from = Column(DateTime, nullable=True,
                        comment="Policy valid from (NULL = always)")
    valid_until = Column(DateTime, nullable=True,
                         comment="Policy valid until (NULL = forever)")

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
    created_by = Column(String(100), nullable=True,
                        comment="Admin who created this policy")

    # Indexes
    __table_args__ = (
        Index('ix_user_policy_subject', 'subject_type', 'subject_id'),
        Index('ix_user_policy_resource', 'resource_type', 'resource_value'),
        Index('ix_user_policy_enabled_priority', 'enabled', 'priority'),
    )

    def __repr__(self):
        return f"<UserAccessPolicy(id={self.id}, name={self.name}, {self.subject_type}:{self.subject_id} -> {self.resource_type}:{self.resource_value})>"