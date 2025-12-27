# control-plane/core/user_policy_manager.py
"""
User Policy Manager - User and Group based access control

Implements Zero Trust access policies for users and groups:
- Domain/URL access control
- Zone/network segment access
- Time-based access windows
- Device type restrictions

Policy evaluation follows:
1. Deny policies take precedence
2. Lower priority number = higher precedence
3. More specific policies override general ones
"""

import json
import logging
from typing import Optional, List, Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_

from database.models import (
    User, Group, UserGroupMembership, UserAccessPolicy, ClientDevice
)
from .events import publish
from .domain_events import EventTypes

logger = logging.getLogger(__name__)


class UserPolicyManager:
    """
    Manages user/group access policies

    Features:
    - CRUD operations for users, groups, policies
    - Policy evaluation for access decisions
    - User-group membership management
    - Time-based and conditional access
    """

    # ==========================================================================
    # User Management
    # ==========================================================================

    def create_user(
        self,
        db: Session,
        user_id: str,
        email: Optional[str] = None,
        display_name: Optional[str] = None,
        department: Optional[str] = None,
        job_title: Optional[str] = None,
        attributes: Optional[Dict[str, Any]] = None
    ) -> User:
        """Create a new user"""
        # Check for existing user
        existing = db.query(User).filter(User.user_id == user_id).first()
        if existing:
            raise ValueError(f"User {user_id} already exists")

        if email:
            email_exists = db.query(User).filter(User.email == email).first()
            if email_exists:
                raise ValueError(f"Email {email} already in use")

        user = User(
            user_id=user_id,
            email=email,
            display_name=display_name or user_id,
            department=department,
            job_title=job_title,
            attributes=json.dumps(attributes) if attributes else None,
            status="active"
        )

        db.add(user)
        db.commit()
        db.refresh(user)

        # Publish event
        publish(
            EventTypes.USER_CREATED,
            {
                "user_id": user.id,
                "user_external_id": user_id,
                "email": email,
                "display_name": display_name,
                "department": department
            },
            source="UserPolicyManager"
        )

        logger.info(f"Created user: {user_id}")
        return user

    def get_user(self, db: Session, user_id: str) -> Optional[User]:
        """Get user by user_id"""
        return db.query(User).filter(User.user_id == user_id).first()

    def get_user_by_id(self, db: Session, id: int) -> Optional[User]:
        """Get user by database ID"""
        return db.query(User).filter(User.id == id).first()

    def list_users(
        self,
        db: Session,
        status: Optional[str] = None,
        department: Optional[str] = None,
        limit: int = 100,
        offset: int = 0
    ) -> List[User]:
        """List users with optional filtering"""
        query = db.query(User)

        if status:
            query = query.filter(User.status == status)
        if department:
            query = query.filter(User.department == department)

        return query.order_by(User.user_id).offset(offset).limit(limit).all()

    def update_user(
        self,
        db: Session,
        user_id: str,
        **updates
    ) -> Optional[User]:
        """Update user attributes"""
        user = self.get_user(db, user_id)
        if not user:
            return None

        allowed_fields = {'display_name', 'email', 'department', 'job_title', 'status', 'attributes'}
        for field, value in updates.items():
            if field in allowed_fields:
                if field == 'attributes' and isinstance(value, dict):
                    value = json.dumps(value)
                setattr(user, field, value)

        user.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(user)

        logger.info(f"Updated user: {user_id}")
        return user

    def delete_user(self, db: Session, user_id: str) -> bool:
        """Delete a user"""
        user = self.get_user(db, user_id)
        if not user:
            return False

        # Remove from all groups first
        db.query(UserGroupMembership).filter(UserGroupMembership.user_id == user.id).delete()

        db.delete(user)
        db.commit()

        logger.info(f"Deleted user: {user_id}")
        return True

    # ==========================================================================
    # Group Management
    # ==========================================================================

    def create_group(
        self,
        db: Session,
        name: str,
        display_name: Optional[str] = None,
        description: Optional[str] = None,
        group_type: str = "team",
        parent_group_id: Optional[int] = None
    ) -> Group:
        """Create a new group"""
        existing = db.query(Group).filter(Group.name == name).first()
        if existing:
            raise ValueError(f"Group {name} already exists")

        group = Group(
            name=name,
            display_name=display_name or name,
            description=description,
            group_type=group_type,
            parent_group_id=parent_group_id,
            status="active"
        )

        db.add(group)
        db.commit()
        db.refresh(group)

        # Publish event
        publish(
            EventTypes.GROUP_CREATED,
            {
                "group_id": group.id,
                "name": name,
                "display_name": display_name,
                "group_type": group_type
            },
            source="UserPolicyManager"
        )

        logger.info(f"Created group: {name}")
        return group

    def get_group(self, db: Session, name: str) -> Optional[Group]:
        """Get group by name"""
        return db.query(Group).filter(Group.name == name).first()

    def get_group_by_id(self, db: Session, id: int) -> Optional[Group]:
        """Get group by database ID"""
        return db.query(Group).filter(Group.id == id).first()

    def list_groups(
        self,
        db: Session,
        group_type: Optional[str] = None,
        parent_id: Optional[int] = None
    ) -> List[Group]:
        """List groups with optional filtering"""
        query = db.query(Group).filter(Group.status == "active")

        if group_type:
            query = query.filter(Group.group_type == group_type)
        if parent_id is not None:
            query = query.filter(Group.parent_group_id == parent_id)

        return query.order_by(Group.name).all()

    def add_user_to_group(
        self,
        db: Session,
        user_id: str,
        group_name: str,
        role: str = "member"
    ) -> bool:
        """Add a user to a group"""
        user = self.get_user(db, user_id)
        group = self.get_group(db, group_name)

        if not user or not group:
            return False

        # Check if already a member
        existing = db.query(UserGroupMembership).filter(
            and_(
                UserGroupMembership.user_id == user.id,
                UserGroupMembership.group_id == group.id
            )
        ).first()

        if existing:
            existing.role = role
            db.commit()
            return True

        membership = UserGroupMembership(
            user_id=user.id,
            group_id=group.id,
            role=role
        )
        db.add(membership)
        db.commit()

        # Publish event
        publish(
            EventTypes.USER_ADDED_TO_GROUP,
            {
                "user_id": user.id,
                "user_external_id": user_id,
                "group_id": group.id,
                "group_name": group_name,
                "role": role
            },
            source="UserPolicyManager"
        )

        logger.info(f"Added user {user_id} to group {group_name} as {role}")
        return True

    def remove_user_from_group(
        self,
        db: Session,
        user_id: str,
        group_name: str
    ) -> bool:
        """Remove a user from a group"""
        user = self.get_user(db, user_id)
        group = self.get_group(db, group_name)

        if not user or not group:
            return False

        result = db.query(UserGroupMembership).filter(
            and_(
                UserGroupMembership.user_id == user.id,
                UserGroupMembership.group_id == group.id
            )
        ).delete()

        db.commit()
        return result > 0

    def get_user_groups(self, db: Session, user_id: str) -> List[Group]:
        """Get all groups a user belongs to"""
        user = self.get_user(db, user_id)
        if not user:
            return []

        memberships = db.query(UserGroupMembership).filter(
            UserGroupMembership.user_id == user.id
        ).all()

        group_ids = [m.group_id for m in memberships]
        return db.query(Group).filter(Group.id.in_(group_ids)).all() if group_ids else []

    def get_group_members(self, db: Session, group_name: str) -> List[User]:
        """Get all members of a group"""
        group = self.get_group(db, group_name)
        if not group:
            return []

        memberships = db.query(UserGroupMembership).filter(
            UserGroupMembership.group_id == group.id
        ).all()

        user_ids = [m.user_id for m in memberships]
        return db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []

    # ==========================================================================
    # Policy Management
    # ==========================================================================

    def create_policy(
        self,
        db: Session,
        name: str,
        subject_type: str,  # "user", "group", "all"
        resource_type: str,  # "domain", "ip_range", "zone", "service"
        resource_value: str,
        action: str = "allow",
        subject_id: Optional[int] = None,
        description: Optional[str] = None,
        conditions: Optional[Dict[str, Any]] = None,
        priority: int = 100,
        valid_from: Optional[datetime] = None,
        valid_until: Optional[datetime] = None,
        created_by: Optional[str] = None
    ) -> UserAccessPolicy:
        """Create a new user access policy"""

        # Validate subject_type
        if subject_type not in ("user", "group", "all"):
            raise ValueError(f"Invalid subject_type: {subject_type}")

        # Validate resource_type
        valid_resource_types = ("domain", "ip_range", "zone", "service", "url_pattern")
        if resource_type not in valid_resource_types:
            raise ValueError(f"Invalid resource_type: {resource_type}")

        # Validate action
        if action not in ("allow", "deny", "require_mfa"):
            raise ValueError(f"Invalid action: {action}")

        policy = UserAccessPolicy(
            name=name,
            description=description,
            subject_type=subject_type,
            subject_id=subject_id,
            resource_type=resource_type,
            resource_value=resource_value,
            action=action,
            conditions=json.dumps(conditions) if conditions else None,
            priority=priority,
            enabled=True,
            valid_from=valid_from,
            valid_until=valid_until,
            created_by=created_by
        )

        db.add(policy)
        db.commit()
        db.refresh(policy)

        # Publish event
        publish(
            EventTypes.POLICY_CREATED,
            {
                "policy_id": policy.id,
                "policy_name": policy.name,
                "subject_type": subject_type,
                "subject_id": subject_id,
                "resource_type": resource_type,
                "resource_value": resource_value,
                "action": action
            },
            source="UserPolicyManager"
        )

        logger.info(f"Created policy: {name}")
        return policy

    def get_policy(self, db: Session, policy_id: int) -> Optional[UserAccessPolicy]:
        """Get policy by ID"""
        return db.query(UserAccessPolicy).filter(UserAccessPolicy.id == policy_id).first()

    def list_policies(
        self,
        db: Session,
        subject_type: Optional[str] = None,
        subject_id: Optional[int] = None,
        resource_type: Optional[str] = None,
        enabled_only: bool = True
    ) -> List[UserAccessPolicy]:
        """List policies with optional filtering"""
        query = db.query(UserAccessPolicy)

        if enabled_only:
            query = query.filter(UserAccessPolicy.enabled == True)
        if subject_type:
            query = query.filter(UserAccessPolicy.subject_type == subject_type)
        if subject_id is not None:
            query = query.filter(UserAccessPolicy.subject_id == subject_id)
        if resource_type:
            query = query.filter(UserAccessPolicy.resource_type == resource_type)

        return query.order_by(UserAccessPolicy.priority).all()

    def update_policy(
        self,
        db: Session,
        policy_id: int,
        **updates
    ) -> Optional[UserAccessPolicy]:
        """Update policy attributes"""
        policy = self.get_policy(db, policy_id)
        if not policy:
            return None

        allowed_fields = {
            'name', 'description', 'resource_value', 'action',
            'conditions', 'priority', 'enabled', 'valid_from', 'valid_until'
        }

        for field, value in updates.items():
            if field in allowed_fields:
                if field == 'conditions' and isinstance(value, dict):
                    value = json.dumps(value)
                setattr(policy, field, value)

        policy.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(policy)

        # Publish event
        publish(
            EventTypes.POLICY_UPDATED,
            {
                "policy_id": policy.id,
                "policy_name": policy.name,
                "changes": list(updates.keys())
            },
            source="UserPolicyManager"
        )

        logger.info(f"Updated policy: {policy_id}")
        return policy

    def delete_policy(self, db: Session, policy_id: int) -> bool:
        """Delete a policy"""
        policy = self.get_policy(db, policy_id)
        if not policy:
            return False

        policy_name = policy.name
        db.delete(policy)
        db.commit()

        # Publish event
        publish(
            EventTypes.POLICY_DELETED,
            {"policy_id": policy_id, "policy_name": policy_name},
            source="UserPolicyManager"
        )

        logger.info(f"Deleted policy: {policy_id}")
        return True

    # ==========================================================================
    # Policy Evaluation
    # ==========================================================================

    def evaluate_access(
        self,
        db: Session,
        user_id: str,
        resource_type: str,
        resource_value: str,
        device_type: Optional[str] = None,
        client_ip: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Evaluate whether a user can access a resource

        Returns:
            {
                "allowed": bool,
                "action": "allow" | "deny" | "require_mfa",
                "matched_policy": policy_id or None,
                "reason": str
            }
        """
        user = self.get_user(db, user_id)
        if not user:
            return {
                "allowed": False,
                "action": "deny",
                "matched_policy": None,
                "reason": "User not found"
            }

        if user.status != "active":
            return {
                "allowed": False,
                "action": "deny",
                "matched_policy": None,
                "reason": f"User status is {user.status}"
            }

        # Get user's groups
        user_groups = self.get_user_groups(db, user_id)
        group_ids = [g.id for g in user_groups]

        # Build query for applicable policies
        now = datetime.utcnow()

        # Find all potentially applicable policies
        query = db.query(UserAccessPolicy).filter(
            and_(
                UserAccessPolicy.enabled == True,
                UserAccessPolicy.resource_type == resource_type,
                or_(
                    UserAccessPolicy.valid_from.is_(None),
                    UserAccessPolicy.valid_from <= now
                ),
                or_(
                    UserAccessPolicy.valid_until.is_(None),
                    UserAccessPolicy.valid_until >= now
                )
            )
        )

        policies = query.order_by(UserAccessPolicy.priority).all()

        # Evaluate policies in priority order
        for policy in policies:
            # Check if policy applies to this user
            if not self._policy_applies_to_user(policy, user.id, group_ids):
                continue

            # Check if resource matches
            if not self._resource_matches(policy.resource_value, resource_value):
                continue

            # Check conditions
            if policy.conditions:
                conditions = json.loads(policy.conditions)
                if not self._evaluate_conditions(conditions, device_type, client_ip, now):
                    continue

            # Policy matches!
            is_allowed = policy.action in ("allow", "require_mfa")

            return {
                "allowed": is_allowed,
                "action": policy.action,
                "matched_policy": policy.id,
                "reason": f"Matched policy: {policy.name}"
            }

        # No matching policy - default deny (Zero Trust)
        return {
            "allowed": False,
            "action": "deny",
            "matched_policy": None,
            "reason": "No matching policy found (default deny)"
        }

    def _policy_applies_to_user(
        self,
        policy: UserAccessPolicy,
        user_db_id: int,
        group_ids: List[int]
    ) -> bool:
        """Check if a policy applies to a specific user"""
        if policy.subject_type == "all":
            return True
        elif policy.subject_type == "user":
            return policy.subject_id == user_db_id
        elif policy.subject_type == "group":
            return policy.subject_id in group_ids
        return False

    def _resource_matches(self, pattern: str, resource: str) -> bool:
        """
        Check if resource matches pattern

        Supports:
        - Exact match: "example.com" matches "example.com"
        - Wildcard: "*.example.com" matches "api.example.com"
        - CIDR: "10.0.0.0/24" matches "10.0.0.5"
        """
        import fnmatch
        import ipaddress

        # Try CIDR match for IP addresses
        if '/' in pattern:
            try:
                network = ipaddress.ip_network(pattern, strict=False)
                ip = ipaddress.ip_address(resource)
                return ip in network
            except ValueError:
                pass

        # Wildcard/glob match
        return fnmatch.fnmatch(resource.lower(), pattern.lower())

    def _evaluate_conditions(
        self,
        conditions: Dict[str, Any],
        device_type: Optional[str],
        client_ip: Optional[str],
        now: datetime
    ) -> bool:
        """Evaluate policy conditions"""

        # Check device type
        if "device_types" in conditions:
            allowed_types = conditions["device_types"]
            if device_type and device_type not in allowed_types:
                return False

        # Check time windows
        if "time_windows" in conditions:
            for window in conditions["time_windows"]:
                # Format: {"days": [0,1,2,3,4], "start": "09:00", "end": "18:00"}
                day_of_week = now.weekday()
                if "days" in window and day_of_week not in window["days"]:
                    continue

                current_time = now.strftime("%H:%M")
                start = window.get("start", "00:00")
                end = window.get("end", "23:59")

                if start <= current_time <= end:
                    return True

            return False  # No matching time window

        # Check IP restrictions
        if "allowed_ips" in conditions and client_ip:
            import ipaddress
            for pattern in conditions["allowed_ips"]:
                try:
                    if '/' in pattern:
                        network = ipaddress.ip_network(pattern, strict=False)
                        if ipaddress.ip_address(client_ip) in network:
                            return True
                    elif pattern == client_ip:
                        return True
                except ValueError:
                    pass
            return False

        return True  # All conditions passed

    def get_user_effective_policies(
        self,
        db: Session,
        user_id: str,
        resource_type: Optional[str] = None
    ) -> List[UserAccessPolicy]:
        """
        Get all effective policies for a user (direct + from group memberships)

        Returns policies sorted by priority.
        """
        user = self.get_user(db, user_id)
        if not user:
            return []

        # Get user's groups
        user_groups = self.get_user_groups(db, user_id)
        group_ids = [g.id for g in user_groups]

        now = datetime.utcnow()

        # Query for all applicable policies
        query = db.query(UserAccessPolicy).filter(
            and_(
                UserAccessPolicy.enabled == True,
                or_(
                    UserAccessPolicy.valid_from.is_(None),
                    UserAccessPolicy.valid_from <= now
                ),
                or_(
                    UserAccessPolicy.valid_until.is_(None),
                    UserAccessPolicy.valid_until >= now
                ),
                or_(
                    UserAccessPolicy.subject_type == "all",
                    and_(
                        UserAccessPolicy.subject_type == "user",
                        UserAccessPolicy.subject_id == user.id
                    ),
                    and_(
                        UserAccessPolicy.subject_type == "group",
                        UserAccessPolicy.subject_id.in_(group_ids) if group_ids else False
                    )
                )
            )
        )

        if resource_type:
            query = query.filter(UserAccessPolicy.resource_type == resource_type)

        return query.order_by(UserAccessPolicy.priority).all()


# Singleton instance
user_policy_manager = UserPolicyManager()
