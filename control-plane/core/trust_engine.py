# control-plane/core/trust_engine.py
"""
Trust Engine for Zero Trust Control Plane
Implements Dynamic Trust Scoring per NIST SP 800-207

Trust Score Formula:
TrustScore = (RoleBase * 0.4) + (DeviceHealth * 0.3) + (Behavior * 0.2) + (SecurityEvents * 0.1)

Actions based on trust score:
- 1.0 - 0.8: Full access
- 0.8 - 0.6: Normal access with monitoring
- 0.6 - 0.4: Limited access (reduced ACL)
- 0.4 - 0.2: Suspended (no new connections)
- 0.2 - 0.0: Revoked (remove peer)
"""

import json
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, Tuple, List
from sqlalchemy.orm import Session

from database.models import Node, NodeStatus, TrustHistory
from config import settings

logger = logging.getLogger(__name__)


class TrustEngine:
    """
    Dynamic Trust Scoring Engine
    Calculates and manages trust scores for all nodes
    """

    # Trust thresholds
    THRESHOLD_FULL_ACCESS = 0.8
    THRESHOLD_NORMAL = 0.6
    THRESHOLD_LIMITED = 0.4
    THRESHOLD_SUSPEND = 0.2

    # Weight configuration
    WEIGHT_ROLE = 0.4
    WEIGHT_DEVICE_HEALTH = 0.3
    WEIGHT_BEHAVIOR = 0.2
    WEIGHT_SECURITY = 0.1

    # Role base scores (inherent trust level)
    ROLE_BASE_SCORES = {
        'hub': 1.0,
        'ops': 0.9,
        'monitor': 0.85,
        'app': 0.8,
        'db': 0.75,
        'gateway': 0.7,
        'default': 0.5
    }

    def __init__(self):
        self.wireguard_service = None  # Lazy load to avoid circular imports

    def calculate_trust_score(
        self,
        node: Node,
        metrics: Dict[str, Any]
    ) -> Tuple[float, Dict[str, Any]]:
        """
        Calculate trust score for a node based on current metrics

        Args:
            node: Node object
            metrics: Dict containing cpu_percent, memory_percent, disk_percent,
                     security_events, network_stats, etc.

        Returns:
            Tuple of (trust_score, factor_breakdown)
        """
        factors = {}

        # 1. Role-based base score (40%)
        role_score = self.ROLE_BASE_SCORES.get(node.role, self.ROLE_BASE_SCORES['default'])
        factors['role_score'] = role_score

        # 2. Device Health Score (30%)
        device_health = self._calculate_device_health(metrics)
        factors['device_health_score'] = device_health

        # 3. Behavioral Score (20%)
        behavior_score = self._calculate_behavior_score(node, metrics)
        factors['behavior_score'] = behavior_score

        # 4. Security Events Score (10%)
        security_score = self._calculate_security_score(metrics)
        factors['security_score'] = security_score

        # Calculate weighted total
        trust_score = (
            (role_score * self.WEIGHT_ROLE) +
            (device_health * self.WEIGHT_DEVICE_HEALTH) +
            (behavior_score * self.WEIGHT_BEHAVIOR) +
            (security_score * self.WEIGHT_SECURITY)
        )

        # Clamp to 0-1 range
        trust_score = max(0.0, min(1.0, trust_score))
        factors['total_score'] = trust_score

        # Determine risk level
        factors['risk_level'] = self._get_risk_level(metrics)
        factors['risk_factors'] = self._get_risk_factors(metrics)

        return trust_score, factors

    def _calculate_device_health(self, metrics: Dict[str, Any]) -> float:
        """
        Calculate device health score based on resource usage
        High CPU/Memory/Disk = lower score (potential compromise)
        """
        score = 1.0
        penalties = []

        cpu = metrics.get('cpu_percent', 0)
        memory = metrics.get('memory_percent', 0)
        disk = metrics.get('disk_percent', 0)

        # CPU penalties
        if cpu > 95:
            score -= 0.4
            penalties.append('cpu_critical')
        elif cpu > 85:
            score -= 0.2
            penalties.append('cpu_high')
        elif cpu > 70:
            score -= 0.1
            penalties.append('cpu_elevated')

        # Memory penalties
        if memory > 95:
            score -= 0.3
            penalties.append('memory_critical')
        elif memory > 85:
            score -= 0.15
            penalties.append('memory_high')
        elif memory > 75:
            score -= 0.05
            penalties.append('memory_elevated')

        # Disk penalties
        if disk > 95:
            score -= 0.3
            penalties.append('disk_critical')
        elif disk > 90:
            score -= 0.15
            penalties.append('disk_high')

        return max(0.0, score)

    def _calculate_behavior_score(self, node: Node, metrics: Dict[str, Any]) -> float:
        """
        Calculate behavioral score based on connection patterns
        Anomalies lower the score
        """
        score = 1.0

        # Check last seen - node should report regularly
        if node.last_seen:
            time_since_seen = (datetime.utcnow() - node.last_seen).total_seconds()
            if time_since_seen > 300:  # 5 minutes
                score -= 0.2
            elif time_since_seen > 180:  # 3 minutes
                score -= 0.1

        # Network stats analysis
        network = metrics.get('network_stats', {})
        connections = network.get('connections', {})

        # Too many connections could be suspicious
        total_conn = connections.get('total', 0)
        if total_conn > 500:
            score -= 0.3
        elif total_conn > 200:
            score -= 0.1

        # High TIME_WAIT could indicate scan/attack
        time_wait = connections.get('time_wait', 0)
        if time_wait > 100:
            score -= 0.2
        elif time_wait > 50:
            score -= 0.1

        return max(0.0, score)

    def _calculate_security_score(self, metrics: Dict[str, Any]) -> float:
        """
        Calculate security score based on security events
        Security incidents heavily penalize the score
        """
        score = 1.0

        security = metrics.get('security_events', {})
        summary = security.get('summary', {})
        risk_level = summary.get('risk_level', 'low')
        risk_factors = summary.get('risk_factors', [])

        # Risk level penalties
        if risk_level == 'critical':
            score -= 0.8
        elif risk_level == 'high':
            score -= 0.5
        elif risk_level == 'medium':
            score -= 0.3

        # Specific factor penalties
        factor_penalties = {
            'ssh_brute_force': 0.4,
            'ssh_failed_logins': 0.15,
            'port_scan': 0.3,
            'high_blocked_connections': 0.2,
            'wireguard_failures': 0.25,
            'suspicious_processes': 0.5,
            'high_cpu_usage': 0.1
        }

        for factor in risk_factors:
            if factor in factor_penalties:
                score -= factor_penalties[factor]

        return max(0.0, score)

    def _get_risk_level(self, metrics: Dict[str, Any]) -> str:
        """Get risk level from security events"""
        security = metrics.get('security_events', {})
        return security.get('summary', {}).get('risk_level', 'low')

    def _get_risk_factors(self, metrics: Dict[str, Any]) -> List[str]:
        """Get list of risk factors"""
        security = metrics.get('security_events', {})
        return security.get('summary', {}).get('risk_factors', [])

    def update_node_trust(
        self,
        db: Session,
        node: Node,
        metrics: Dict[str, Any],
        record_history: bool = True
    ) -> Tuple[float, str]:
        """
        Update node's trust score and take action if needed

        Returns:
            Tuple of (new_trust_score, action_taken)
        """
        previous_score = node.trust_score or 1.0

        # Calculate new trust score
        new_score, factors = self.calculate_trust_score(node, metrics)

        # Update node
        node.trust_score = new_score
        node.trust_factors = json.dumps(factors)
        node.last_trust_update = datetime.utcnow()
        node.risk_level = factors.get('risk_level', 'low')

        # Determine action based on score
        action = self._determine_action(node, new_score, previous_score)

        # Record history
        if record_history:
            self._record_trust_history(
                db, node, new_score, previous_score,
                factors, metrics, action
            )

        # Execute action
        self._execute_action(db, node, action)

        db.commit()

        logger.info(
            f"Trust update for {node.hostname}: "
            f"{previous_score:.2f} -> {new_score:.2f} "
            f"(risk: {factors.get('risk_level')}, action: {action})"
        )

        return new_score, action

    def _determine_action(
        self,
        node: Node,
        new_score: float,
        previous_score: float
    ) -> str:
        """Determine what action to take based on trust score"""

        # Critical drop detection (sudden trust loss)
        score_drop = previous_score - new_score
        if score_drop > 0.3:
            logger.warning(f"Critical trust drop for {node.hostname}: {score_drop:.2f}")
            if new_score < self.THRESHOLD_SUSPEND:
                return 'revoke'
            return 'suspend'

        # Score-based actions
        if new_score < self.THRESHOLD_SUSPEND:
            return 'revoke'
        elif new_score < self.THRESHOLD_LIMITED:
            return 'suspend'
        elif new_score < self.THRESHOLD_NORMAL:
            return 'rate_limit'
        elif new_score < self.THRESHOLD_FULL_ACCESS:
            return 'warning'

        return 'none'

    def _execute_action(self, db: Session, node: Node, action: str):
        """Execute the determined action"""

        if action == 'none' or action == 'warning':
            return

        if action == 'rate_limit':
            # TODO: Implement rate limiting
            logger.info(f"Rate limiting {node.hostname}")
            return

        if action == 'suspend':
            if node.status != NodeStatus.SUSPENDED.value:
                node.status = NodeStatus.SUSPENDED.value
                logger.warning(f"Suspending node {node.hostname} due to low trust score")
                # Remove from WireGuard but keep in DB
                self._remove_wireguard_peer(node.public_key)

        if action == 'revoke':
            if node.status != NodeStatus.REVOKED.value:
                node.status = NodeStatus.REVOKED.value
                logger.error(f"Revoking node {node.hostname} due to critical trust score")
                self._remove_wireguard_peer(node.public_key)

    def _remove_wireguard_peer(self, public_key: str):
        """Remove peer from WireGuard"""
        try:
            if self.wireguard_service is None:
                from .wireguard_service import wireguard_service
                self.wireguard_service = wireguard_service

            self.wireguard_service.remove_peer(public_key, save_config=True)
        except Exception as e:
            logger.error(f"Failed to remove WireGuard peer: {e}")

    def _record_trust_history(
        self,
        db: Session,
        node: Node,
        new_score: float,
        previous_score: float,
        factors: Dict[str, Any],
        metrics: Dict[str, Any],
        action: str
    ):
        """Record trust score change in history"""
        try:
            history = TrustHistory(
                node_id=node.id,
                hostname=node.hostname,
                trust_score=new_score,
                previous_score=previous_score,
                risk_level=factors.get('risk_level', 'low'),
                risk_factors=json.dumps(factors.get('risk_factors', [])),
                device_health_score=factors.get('device_health_score'),
                security_score=factors.get('security_score'),
                behavior_score=factors.get('behavior_score'),
                role_score=factors.get('role_score'),
                metrics_snapshot=json.dumps({
                    'cpu': metrics.get('cpu_percent'),
                    'memory': metrics.get('memory_percent'),
                    'disk': metrics.get('disk_percent'),
                    'security_summary': metrics.get('security_events', {}).get('summary')
                }),
                action_taken=action
            )
            db.add(history)
        except Exception as e:
            logger.warning(f"Failed to record trust history: {e}")

    def get_trust_trend(
        self,
        db: Session,
        node_id: int,
        hours: int = 24
    ) -> Dict[str, Any]:
        """Get trust score trend for a node"""
        since = datetime.utcnow() - timedelta(hours=hours)

        history = db.query(TrustHistory).filter(
            TrustHistory.node_id == node_id,
            TrustHistory.created_at >= since
        ).order_by(TrustHistory.created_at.desc()).all()

        if not history:
            return {'trend': 'stable', 'data': []}

        scores = [h.trust_score for h in history]
        avg_score = sum(scores) / len(scores)

        # Determine trend
        if len(scores) >= 2:
            recent = sum(scores[:len(scores)//2]) / (len(scores)//2)
            older = sum(scores[len(scores)//2:]) / (len(scores) - len(scores)//2)

            if recent > older + 0.1:
                trend = 'improving'
            elif recent < older - 0.1:
                trend = 'declining'
            else:
                trend = 'stable'
        else:
            trend = 'stable'

        return {
            'trend': trend,
            'average': avg_score,
            'min': min(scores),
            'max': max(scores),
            'data_points': len(scores),
            'data': [
                {
                    'timestamp': h.created_at.isoformat(),
                    'score': h.trust_score,
                    'risk_level': h.risk_level
                }
                for h in history[:50]  # Last 50 entries
            ]
        }


# Singleton instance
trust_engine = TrustEngine()
