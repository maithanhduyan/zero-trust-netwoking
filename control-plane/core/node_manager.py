# control-plane/core/node_manager.py
"""
Node Manager - Handles node registration and lifecycle
"""

from typing import Optional, Tuple, List
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from datetime import datetime
import logging

from database.models import Node, NodeStatus, AuditLog
from config import settings
from .ipam import ipam_service
from .wireguard_service import wireguard_service

logger = logging.getLogger(__name__)


class NodeManager:
    """
    Node Manager for handling node registration and lifecycle

    Responsibilities:
    1. Register new nodes
    2. Allocate overlay IPs
    3. Approve/suspend/revoke nodes
    4. Track node status
    """

    def __init__(self):
        self.hub_public_key = settings.HUB_PUBLIC_KEY
        self.hub_endpoint = settings.HUB_ENDPOINT

    def register_node(
        self,
        db: Session,
        hostname: str,
        role: str,
        public_key: str,
        description: Optional[str] = None,
        agent_version: Optional[str] = None,
        os_info: Optional[str] = None,
        client_ip: Optional[str] = None
    ) -> Tuple[Node, bool]:
        """
        Register a new node or return existing node

        Args:
            db: Database session
            hostname: Unique hostname
            role: Node role (app, db, ops, etc.)
            public_key: WireGuard public key
            description: Optional description
            agent_version: Agent version
            os_info: Operating system info
            client_ip: Client's real IP address

        Returns:
            Tuple of (Node, is_new)

        Raises:
            ValueError: If validation fails
            RuntimeError: If IP allocation fails
        """
        # Check for existing node by public key (re-registration)
        existing_by_key = db.query(Node).filter(
            Node.public_key == public_key
        ).first()

        if existing_by_key:
            # Same key - update last_seen and return
            existing_by_key.last_seen = datetime.utcnow()
            if client_ip:
                existing_by_key.real_ip = client_ip
            if agent_version:
                existing_by_key.agent_version = agent_version
            db.commit()
            logger.info(f"Node re-registered: {existing_by_key.hostname}")

            # Ensure peer exists in WireGuard (for re-registration after Hub restart)
            if existing_by_key.status == NodeStatus.ACTIVE.value:
                overlay_ip_only = existing_by_key.overlay_ip.split('/')[0]
                if not wireguard_service.peer_exists(public_key):
                    if wireguard_service.add_peer(public_key, f"{overlay_ip_only}/32"):
                        logger.info(f"Re-added WireGuard peer for {existing_by_key.hostname}")

            return existing_by_key, False

        # Check for existing node by hostname
        existing_by_hostname = db.query(Node).filter(
            Node.hostname == hostname
        ).first()

        if existing_by_hostname:
            raise ValueError(f"Hostname '{hostname}' is already registered with a different key")

        # Allocate new IP
        try:
            overlay_ip = ipam_service.allocate_ip_with_cidr(db)
        except RuntimeError as e:
            logger.error(f"Failed to allocate IP: {e}")
            raise

        # Determine initial status
        initial_status = self._determine_initial_status(role)
        is_approved = initial_status == NodeStatus.ACTIVE.value

        # Create new node
        new_node = Node(
            hostname=hostname,
            role=role,
            public_key=public_key,
            description=description,
            overlay_ip=overlay_ip,
            real_ip=client_ip,
            status=initial_status,
            is_approved=is_approved,
            agent_version=agent_version,
            os_info=os_info,
            last_seen=datetime.utcnow(),
            config_version=1
        )

        try:
            db.add(new_node)
            db.commit()
            db.refresh(new_node)

            # Audit log
            self._log_event(
                db,
                event_type="registration",
                event_action="create",
                actor_type="node",
                actor_id=hostname,
                actor_ip=client_ip,
                target_type="node",
                target_id=str(new_node.id),
                status="success"
            )

            logger.info(f"New node registered: {hostname} -> {overlay_ip}")

            # Auto-add peer to WireGuard if node is active
            if new_node.status == NodeStatus.ACTIVE.value:
                overlay_ip_only = overlay_ip.split('/')[0]
                if wireguard_service.add_peer(public_key, f"{overlay_ip_only}/32"):
                    logger.info(f"Added WireGuard peer for {hostname}")
                else:
                    logger.warning(f"Failed to add WireGuard peer for {hostname}")

            return new_node, True

        except IntegrityError as e:
            db.rollback()
            logger.error(f"Database error during registration: {e}")
            raise ValueError("Registration failed due to database constraint")

    def _determine_initial_status(self, role: str) -> str:
        """
        Determine initial status based on role and settings
        """
        if settings.AUTO_APPROVE_ALL:
            return NodeStatus.ACTIVE.value

        if role in settings.AUTO_APPROVE_ROLES:
            return NodeStatus.ACTIVE.value

        return NodeStatus.PENDING.value

    def approve_node(self, db: Session, node_id: int, admin_id: Optional[str] = None) -> Node:
        """
        Approve a pending node
        """
        node = db.query(Node).filter(Node.id == node_id).first()
        if not node:
            raise ValueError(f"Node with id {node_id} not found")

        node.status = NodeStatus.ACTIVE.value
        node.is_approved = True
        node.updated_at = datetime.utcnow()
        db.commit()

        self._log_event(
            db,
            event_type="approval",
            event_action="update",
            actor_type="admin",
            actor_id=admin_id,
            target_type="node",
            target_id=str(node_id),
            status="success"
        )

        logger.info(f"Node approved: {node.hostname}")
        return node

    def suspend_node(self, db: Session, node_id: int, admin_id: Optional[str] = None) -> Node:
        """
        Suspend an active node
        """
        node = db.query(Node).filter(Node.id == node_id).first()
        if not node:
            raise ValueError(f"Node with id {node_id} not found")

        node.status = NodeStatus.SUSPENDED.value
        node.is_approved = False
        node.updated_at = datetime.utcnow()
        db.commit()

        self._log_event(
            db,
            event_type="suspension",
            event_action="update",
            actor_type="admin",
            actor_id=admin_id,
            target_type="node",
            target_id=str(node_id),
            status="success"
        )

        logger.info(f"Node suspended: {node.hostname}")
        return node

    def revoke_node(self, db: Session, node_id: int, admin_id: Optional[str] = None) -> Node:
        """
        Permanently revoke a node
        """
        node = db.query(Node).filter(Node.id == node_id).first()
        if not node:
            raise ValueError(f"Node with id {node_id} not found")

        node.status = NodeStatus.REVOKED.value
        node.is_approved = False
        node.updated_at = datetime.utcnow()
        db.commit()

        self._log_event(
            db,
            event_type="revocation",
            event_action="update",
            actor_type="admin",
            actor_id=admin_id,
            target_type="node",
            target_id=str(node_id),
            status="success"
        )

        logger.info(f"Node revoked: {node.hostname}")
        return node

    def delete_node(self, db: Session, node_id: int, admin_id: Optional[str] = None) -> bool:
        """
        Delete a node completely
        """
        node = db.query(Node).filter(Node.id == node_id).first()
        if not node:
            return False

        hostname = node.hostname
        overlay_ip = node.overlay_ip

        db.delete(node)
        db.commit()

        # Release IP
        if overlay_ip:
            ipam_service.release_ip(db, overlay_ip)

        self._log_event(
            db,
            event_type="deletion",
            event_action="delete",
            actor_type="admin",
            actor_id=admin_id,
            target_type="node",
            target_id=str(node_id),
            status="success"
        )

        logger.info(f"Node deleted: {hostname}")
        return True

    def get_node_by_hostname(self, db: Session, hostname: str) -> Optional[Node]:
        """Get node by hostname"""
        return db.query(Node).filter(Node.hostname == hostname).first()

    def get_node_by_public_key(self, db: Session, public_key: str) -> Optional[Node]:
        """Get node by public key"""
        return db.query(Node).filter(Node.public_key == public_key).first()

    def get_node_by_id(self, db: Session, node_id: int) -> Optional[Node]:
        """Get node by ID"""
        return db.query(Node).filter(Node.id == node_id).first()

    def get_all_nodes(
        self,
        db: Session,
        status: Optional[str] = None,
        role: Optional[str] = None
    ) -> List[Node]:
        """
        Get all nodes with optional filtering
        """
        query = db.query(Node)

        if status:
            query = query.filter(Node.status == status)
        if role:
            query = query.filter(Node.role == role)

        return query.order_by(Node.created_at.desc()).all()

    def update_heartbeat(
        self,
        db: Session,
        node: Node,
        client_ip: Optional[str] = None,
        agent_version: Optional[str] = None
    ) -> Node:
        """
        Update node heartbeat
        """
        node.last_seen = datetime.utcnow()
        if client_ip:
            node.real_ip = client_ip
        if agent_version:
            node.agent_version = agent_version
        db.commit()
        return node

    def _log_event(
        self,
        db: Session,
        event_type: str,
        event_action: str,
        actor_type: str,
        actor_id: Optional[str],
        target_type: Optional[str] = None,
        target_id: Optional[str] = None,
        actor_ip: Optional[str] = None,
        status: str = "success",
        details: Optional[str] = None
    ):
        """Log an audit event"""
        if not settings.ENABLE_AUDIT_LOG:
            return

        try:
            log = AuditLog(
                event_type=event_type,
                event_action=event_action,
                actor_type=actor_type,
                actor_id=actor_id,
                actor_ip=actor_ip,
                target_type=target_type,
                target_id=target_id,
                status=status,
                details=details
            )
            db.add(log)
            db.commit()
        except Exception as e:
            logger.error(f"Failed to create audit log: {e}")


# Singleton instance
node_manager = NodeManager()


# Legacy constants for backward compatibility
NETWORK_CIDR = settings.OVERLAY_NETWORK
SERVER_IP = settings.OVERLAY_GATEWAY
SERVER_PUBLIC_KEY = settings.HUB_PUBLIC_KEY
SERVER_ENDPOINT = settings.HUB_ENDPOINT


# Legacy functions for backward compatibility
def get_next_ip(db: Session) -> str:
    """Legacy function - use ipam_service.allocate_ip() instead"""
    return ipam_service.allocate_ip(db)


def register_node(db: Session, node_in) -> Node:
    """Legacy function - use node_manager.register_node() instead"""
    node, is_new = node_manager.register_node(
        db=db,
        hostname=node_in.hostname,
        role=node_in.role,
        public_key=node_in.public_key
    )
    return node