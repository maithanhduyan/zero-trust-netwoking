# control-plane/core/policy_engine.py
"""
Policy Engine - Zero Trust Access Control
Compiles high-level policies into concrete firewall rules
"""

from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from datetime import datetime
import logging

from database.models import Node, AccessPolicy, NodeStatus
from config import settings

logger = logging.getLogger(__name__)


class FirewallRule:
    """Compiled firewall rule for Agent"""

    def __init__(
        self,
        src_ip: str,
        port: int,
        proto: str = "tcp",
        action: str = "ACCEPT",
        comment: Optional[str] = None
    ):
        self.src_ip = src_ip
        self.port = port
        self.proto = proto
        self.action = action
        self.comment = comment

    def to_dict(self) -> dict:
        return {
            "src_ip": self.src_ip,
            "port": self.port,
            "proto": self.proto,
            "action": self.action,
            "comment": self.comment
        }


class PolicyEngine:
    """
    Policy Engine for Zero Trust Access Control

    Responsibilities:
    1. Compile high-level policies into firewall rules
    2. Calculate allowed peers for each node
    3. Generate complete configuration for agents

    Follows NIST SP 800-207:
    - Default deny all
    - Explicit allow based on identity and role
    - Per-session access decisions
    """

    # Default policies (used if no policies in DB)
    DEFAULT_POLICIES = [
        # Ops can SSH everywhere
        {"src": "ops", "dst": "*", "port": 22, "proto": "tcp", "action": "ACCEPT"},
        # Ops can access monitoring
        {"src": "ops", "dst": "*", "port": 9100, "proto": "tcp", "action": "ACCEPT"},
        # App can connect to DB
        {"src": "app", "dst": "db", "port": 5432, "proto": "tcp", "action": "ACCEPT"},
        # All nodes can reach hub
        {"src": "*", "dst": "hub", "port": 51820, "proto": "udp", "action": "ACCEPT"},
    ]

    def __init__(self):
        self._config_version = 1

    def get_policies(self, db: Session) -> List[Dict[str, Any]]:
        """
        Get all enabled policies from database
        Falls back to default policies if none exist
        """
        db_policies = db.query(AccessPolicy).filter(
            AccessPolicy.enabled == True
        ).order_by(AccessPolicy.priority).all()

        if db_policies:
            return [
                {
                    "src": p.src_role,
                    "dst": p.dst_role,
                    "port": p.port,
                    "proto": p.protocol,
                    "action": p.action,
                    "name": p.name
                }
                for p in db_policies
            ]

        logger.warning("No policies in database, using defaults")
        return self.DEFAULT_POLICIES

    def get_active_nodes(self, db: Session) -> List[Node]:
        """Get all active nodes"""
        return db.query(Node).filter(
            Node.status == NodeStatus.ACTIVE.value,
            Node.overlay_ip.isnot(None)
        ).all()

    def generate_acl_for_node(
        self,
        db: Session,
        target_node: Node
    ) -> List[FirewallRule]:
        """
        Generate ACL rules for a specific node

        Args:
            db: Database session
            target_node: The node receiving the configuration

        Returns:
            List of FirewallRule objects
        """
        rules = []
        policies = self.get_policies(db)
        active_nodes = self.get_active_nodes(db)

        for policy in policies:
            # Check if this policy applies to target node
            if policy["dst"] != target_node.role and policy["dst"] != "*":
                continue

            # Find all source nodes that match
            for src_node in active_nodes:
                # Skip self
                if src_node.id == target_node.id:
                    continue

                # Check if source role matches
                if policy["src"] != src_node.role and policy["src"] != "*":
                    continue

                # Extract IP without CIDR
                src_ip = src_node.overlay_ip
                if src_ip and '/' in src_ip:
                    src_ip = src_ip.split('/')[0]

                if src_ip:
                    rule = FirewallRule(
                        src_ip=src_ip,
                        port=policy["port"],
                        proto=policy["proto"],
                        action=policy["action"],
                        comment=policy.get("name", f"{src_node.role}->{target_node.role}")
                    )
                    rules.append(rule)

        logger.debug(f"Generated {len(rules)} ACL rules for {target_node.hostname}")
        return rules

    def generate_peers_for_node(
        self,
        db: Session,
        target_node: Node,
        include_hub: bool = True
    ) -> List[dict]:
        """
        Generate WireGuard peer list for a node

        In Hub-and-Spoke model:
        - Spoke nodes only need the Hub as peer
        - Hub needs all spokes as peers

        In Mesh model:
        - Each node needs all other nodes as peers
        """
        peers = []

        if target_node.role == "hub":
            # Hub needs all other nodes as peers
            nodes = self.get_active_nodes(db)
            for node in nodes:
                if node.id == target_node.id:
                    continue

                # Extract IP without CIDR for allowed_ips
                allowed_ip = node.overlay_ip
                if allowed_ip and '/' not in allowed_ip:
                    allowed_ip = f"{allowed_ip}/32"
                elif allowed_ip:
                    # Convert to /32 for peer
                    allowed_ip = f"{allowed_ip.split('/')[0]}/32"

                peers.append({
                    "public_key": node.public_key,
                    "allowed_ips": allowed_ip,
                    "endpoint": f"{node.real_ip}:{node.listen_port}" if node.real_ip else None,
                    "persistent_keepalive": 25
                })
        else:
            # Spoke nodes only need Hub
            if include_hub:
                peers.append({
                    "public_key": settings.HUB_PUBLIC_KEY,
                    "allowed_ips": settings.OVERLAY_NETWORK,
                    "endpoint": settings.HUB_ENDPOINT,
                    "persistent_keepalive": 25
                })

        return peers

    def build_config_for_node(
        self,
        db: Session,
        node: Node
    ) -> Dict[str, Any]:
        """
        Build complete configuration for an Agent

        Returns:
            Dictionary containing peers and acl_rules
        """
        # Generate peers
        peers = self.generate_peers_for_node(db, node)

        # Generate ACL rules
        acl_rules = self.generate_acl_for_node(db, node)

        return {
            "peers": peers,
            "acl_rules": [rule.to_dict() for rule in acl_rules],
            "config_version": self._config_version,
            "generated_at": datetime.utcnow().isoformat()
        }

    def increment_config_version(self):
        """Increment config version when policies change"""
        self._config_version += 1
        return self._config_version

    def validate_policy(self, policy_data: dict) -> tuple[bool, str]:
        """
        Validate a policy before creation

        Returns:
            Tuple of (is_valid, error_message)
        """
        valid_roles = ["hub", "app", "db", "ops", "monitor", "gateway", "*"]

        if policy_data.get("src_role") not in valid_roles:
            return False, f"Invalid src_role. Must be one of: {valid_roles}"

        if policy_data.get("dst_role") not in valid_roles:
            return False, f"Invalid dst_role. Must be one of: {valid_roles}"

        port = policy_data.get("port", 0)
        if not (1 <= port <= 65535):
            return False, "Port must be between 1 and 65535"

        valid_protocols = ["tcp", "udp", "icmp", "any"]
        if policy_data.get("protocol", "tcp") not in valid_protocols:
            return False, f"Invalid protocol. Must be one of: {valid_protocols}"

        return True, "Valid"


# Singleton instance
policy_engine = PolicyEngine()


# Legacy functions for backward compatibility
def generate_acl(target_role: str, all_nodes: list) -> List[dict]:
    """
    Legacy function - generates ACL rules for a role
    Use policy_engine.generate_acl_for_node() instead
    """
    rules = []

    for policy in PolicyEngine.DEFAULT_POLICIES:
        if policy["dst"] == target_role or policy["dst"] == "*":
            for node in all_nodes:
                if hasattr(node, 'is_active') and not node.is_active:
                    continue
                if hasattr(node, 'status') and node.status != NodeStatus.ACTIVE.value:
                    continue
                if policy["src"] != node.role and policy["src"] != "*":
                    continue

                overlay_ip = node.overlay_ip
                if overlay_ip and '/' in overlay_ip:
                    overlay_ip = overlay_ip.split('/')[0]

                if overlay_ip:
                    rules.append({
                        "src_ip": overlay_ip,
                        "port": policy["port"],
                        "proto": policy["proto"],
                        "action": policy["action"]
                    })

    return rules


def build_config_for_node(db: Session, node: Node) -> dict:
    """Legacy function - use policy_engine.build_config_for_node() instead"""
    return policy_engine.build_config_for_node(db, node)