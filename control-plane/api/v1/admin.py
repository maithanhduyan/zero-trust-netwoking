# control-plane/api/v1/admin.py
"""
Admin API Endpoints
RESTful API for administrators to manage nodes and policies
"""

from fastapi import APIRouter, Depends, HTTPException, Header, Query, status
from sqlalchemy.orm import Session
from typing import List, Optional
import logging

from database.session import get_db
from database.models import Node, AccessPolicy, NodeStatus
from schemas.node import (
    NodeResponse,
    NodeUpdate,
    NodeListResponse,
)
from schemas.policy import (
    PolicyCreate,
    PolicyUpdate,
    PolicyResponse,
    PolicyListResponse,
)
from schemas.base import BaseResponse, ErrorResponse
from core.node_manager import node_manager
from core.policy_engine import policy_engine
from core.ipam import ipam_service
from config import settings

logger = logging.getLogger(__name__)

router = APIRouter()


# === Authentication Dependency ===

async def verify_admin_token(x_admin_token: str = Header(..., alias="X-Admin-Token")):
    """
    Verify admin authentication token

    In production, replace with proper JWT/OAuth2 authentication
    """
    if x_admin_token != settings.ADMIN_SECRET:
        logger.warning(f"Invalid admin token attempt")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "error": "Invalid or missing admin token",
                "error_code": "UNAUTHORIZED"
            },
            headers={"WWW-Authenticate": "Bearer"}
        )
    return True


# === Node Management Endpoints ===

@router.get(
    "/nodes",
    response_model=NodeListResponse,
    summary="List all nodes",
    description="Get a list of all registered nodes with optional filtering"
)
async def list_nodes(
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status"),
    role: Optional[str] = Query(None, description="Filter by role"),
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """List all nodes with optional filtering"""
    nodes = node_manager.get_all_nodes(db, status=status_filter, role=role)

    return NodeListResponse(
        nodes=[
            NodeResponse(
                id=node.id,
                hostname=node.hostname,
                role=node.role,
                status=node.status,
                overlay_ip=node.overlay_ip,
                real_ip=node.real_ip,
                public_key=node.public_key,
                description=node.description,
                agent_version=node.agent_version,
                os_info=node.os_info,
                last_seen=node.last_seen,
                created_at=node.created_at,
                updated_at=node.updated_at
            )
            for node in nodes
        ],
        total=len(nodes)
    )


@router.get(
    "/nodes/{node_id}",
    response_model=NodeResponse,
    responses={
        200: {"description": "Node found"},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Get node by ID",
    description="Get detailed information about a specific node"
)
async def get_node(
    node_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Get node details by ID"""
    node = node_manager.get_node_by_id(db, node_id)

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Node with id {node_id} not found",
                "error_code": "NODE_NOT_FOUND"
            }
        )

    return NodeResponse(
        id=node.id,
        hostname=node.hostname,
        role=node.role,
        status=node.status,
        overlay_ip=node.overlay_ip,
        real_ip=node.real_ip,
        public_key=node.public_key,
        description=node.description,
        agent_version=node.agent_version,
        os_info=node.os_info,
        last_seen=node.last_seen,
        created_at=node.created_at,
        updated_at=node.updated_at
    )


@router.patch(
    "/nodes/{node_id}",
    response_model=NodeResponse,
    responses={
        200: {"description": "Node updated"},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Update node",
    description="Update node information (description, status, role)"
)
async def update_node(
    node_id: int,
    node_update: NodeUpdate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Update node information"""
    node = node_manager.get_node_by_id(db, node_id)

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Node with id {node_id} not found",
                "error_code": "NODE_NOT_FOUND"
            }
        )

    # Update fields
    if node_update.description is not None:
        node.description = node_update.description
    if node_update.status is not None:
        node.status = node_update.status.value
        node.is_approved = node_update.status.value == NodeStatus.ACTIVE.value
    if node_update.role is not None:
        node.role = node_update.role.value

    db.commit()
    db.refresh(node)

    logger.info(f"Node {node.hostname} updated")

    return NodeResponse(
        id=node.id,
        hostname=node.hostname,
        role=node.role,
        status=node.status,
        overlay_ip=node.overlay_ip,
        real_ip=node.real_ip,
        public_key=node.public_key,
        description=node.description,
        agent_version=node.agent_version,
        os_info=node.os_info,
        last_seen=node.last_seen,
        created_at=node.created_at,
        updated_at=node.updated_at
    )


@router.post(
    "/nodes/{node_id}/approve",
    response_model=BaseResponse[NodeResponse],
    responses={
        200: {"description": "Node approved"},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Approve node",
    description="Approve a pending node to join the network"
)
async def approve_node(
    node_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Approve a pending node"""
    try:
        node = node_manager.approve_node(db, node_id, admin_id="admin")

        return BaseResponse(
            success=True,
            message=f"Node {node.hostname} approved successfully",
            data=NodeResponse(
                id=node.id,
                hostname=node.hostname,
                role=node.role,
                status=node.status,
                overlay_ip=node.overlay_ip,
                real_ip=node.real_ip,
                public_key=node.public_key,
                description=node.description,
                agent_version=node.agent_version,
                os_info=node.os_info,
                last_seen=node.last_seen,
                created_at=node.created_at,
                updated_at=node.updated_at
            )
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": str(e),
                "error_code": "NODE_NOT_FOUND"
            }
        )


@router.post(
    "/nodes/{node_id}/suspend",
    response_model=BaseResponse[NodeResponse],
    responses={
        200: {"description": "Node suspended"},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Suspend node",
    description="Temporarily suspend an active node"
)
async def suspend_node(
    node_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Suspend an active node"""
    try:
        node = node_manager.suspend_node(db, node_id, admin_id="admin")

        return BaseResponse(
            success=True,
            message=f"Node {node.hostname} suspended",
            data=NodeResponse(
                id=node.id,
                hostname=node.hostname,
                role=node.role,
                status=node.status,
                overlay_ip=node.overlay_ip,
                real_ip=node.real_ip,
                public_key=node.public_key,
                description=node.description,
                agent_version=node.agent_version,
                os_info=node.os_info,
                last_seen=node.last_seen,
                created_at=node.created_at,
                updated_at=node.updated_at
            )
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": str(e),
                "error_code": "NODE_NOT_FOUND"
            }
        )


@router.post(
    "/nodes/{node_id}/revoke",
    response_model=BaseResponse[NodeResponse],
    responses={
        200: {"description": "Node revoked"},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Revoke node",
    description="Permanently revoke a node's access"
)
async def revoke_node(
    node_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Revoke a node permanently"""
    try:
        node = node_manager.revoke_node(db, node_id, admin_id="admin")

        return BaseResponse(
            success=True,
            message=f"Node {node.hostname} revoked",
            data=NodeResponse(
                id=node.id,
                hostname=node.hostname,
                role=node.role,
                status=node.status,
                overlay_ip=node.overlay_ip,
                real_ip=node.real_ip,
                public_key=node.public_key,
                description=node.description,
                agent_version=node.agent_version,
                os_info=node.os_info,
                last_seen=node.last_seen,
                created_at=node.created_at,
                updated_at=node.updated_at
            )
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": str(e),
                "error_code": "NODE_NOT_FOUND"
            }
        )


@router.delete(
    "/nodes/{node_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={
        204: {"description": "Node deleted"},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Delete node",
    description="Permanently delete a node and release its IP"
)
async def delete_node(
    node_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Delete a node"""
    if not node_manager.delete_node(db, node_id, admin_id="admin"):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Node with id {node_id} not found",
                "error_code": "NODE_NOT_FOUND"
            }
        )

    return None


# === Policy Management Endpoints ===

@router.get(
    "/policies",
    response_model=PolicyListResponse,
    summary="List all policies",
    description="Get all access policies"
)
async def list_policies(
    enabled: Optional[bool] = Query(None, description="Filter by enabled status"),
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """List all policies"""
    query = db.query(AccessPolicy)

    if enabled is not None:
        query = query.filter(AccessPolicy.enabled == enabled)

    policies = query.order_by(AccessPolicy.priority).all()

    return PolicyListResponse(
        policies=[
            PolicyResponse(
                id=p.id,
                name=p.name,
                description=p.description,
                src_role=p.src_role,
                dst_role=p.dst_role,
                port=p.port,
                protocol=p.protocol,
                action=p.action,
                priority=p.priority,
                enabled=p.enabled,
                created_at=p.created_at,
                updated_at=p.updated_at
            )
            for p in policies
        ],
        total=len(policies)
    )


@router.post(
    "/policies",
    response_model=PolicyResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        201: {"description": "Policy created"},
        400: {"description": "Invalid policy", "model": ErrorResponse},
        409: {"description": "Policy name exists", "model": ErrorResponse},
    },
    summary="Create policy",
    description="Create a new access policy"
)
async def create_policy(
    policy_in: PolicyCreate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Create a new policy"""
    # Validate policy
    is_valid, error = policy_engine.validate_policy(policy_in.model_dump())
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "error": error,
                "error_code": "INVALID_POLICY"
            }
        )

    # Check for duplicate name
    existing = db.query(AccessPolicy).filter(AccessPolicy.name == policy_in.name).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": f"Policy with name '{policy_in.name}' already exists",
                "error_code": "POLICY_EXISTS"
            }
        )

    # Create policy
    new_policy = AccessPolicy(
        name=policy_in.name,
        description=policy_in.description,
        src_role=policy_in.src_role,
        dst_role=policy_in.dst_role,
        port=policy_in.port,
        protocol=policy_in.protocol.value,
        action=policy_in.action.value,
        priority=policy_in.priority,
        enabled=policy_in.enabled
    )

    db.add(new_policy)
    db.commit()
    db.refresh(new_policy)

    # Increment config version to notify agents
    policy_engine.increment_config_version()

    logger.info(f"Policy created: {new_policy.name}")

    return PolicyResponse(
        id=new_policy.id,
        name=new_policy.name,
        description=new_policy.description,
        src_role=new_policy.src_role,
        dst_role=new_policy.dst_role,
        port=new_policy.port,
        protocol=new_policy.protocol,
        action=new_policy.action,
        priority=new_policy.priority,
        enabled=new_policy.enabled,
        created_at=new_policy.created_at,
        updated_at=new_policy.updated_at
    )


@router.get(
    "/policies/{policy_id}",
    response_model=PolicyResponse,
    responses={
        200: {"description": "Policy found"},
        404: {"description": "Policy not found", "model": ErrorResponse},
    },
    summary="Get policy",
    description="Get a specific policy by ID"
)
async def get_policy(
    policy_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Get policy by ID"""
    policy = db.query(AccessPolicy).filter(AccessPolicy.id == policy_id).first()

    if not policy:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Policy with id {policy_id} not found",
                "error_code": "POLICY_NOT_FOUND"
            }
        )

    return PolicyResponse(
        id=policy.id,
        name=policy.name,
        description=policy.description,
        src_role=policy.src_role,
        dst_role=policy.dst_role,
        port=policy.port,
        protocol=policy.protocol,
        action=policy.action,
        priority=policy.priority,
        enabled=policy.enabled,
        created_at=policy.created_at,
        updated_at=policy.updated_at
    )


@router.patch(
    "/policies/{policy_id}",
    response_model=PolicyResponse,
    responses={
        200: {"description": "Policy updated"},
        404: {"description": "Policy not found", "model": ErrorResponse},
    },
    summary="Update policy",
    description="Update an existing policy"
)
async def update_policy(
    policy_id: int,
    policy_update: PolicyUpdate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Update a policy"""
    policy = db.query(AccessPolicy).filter(AccessPolicy.id == policy_id).first()

    if not policy:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Policy with id {policy_id} not found",
                "error_code": "POLICY_NOT_FOUND"
            }
        )

    # Update fields
    update_data = policy_update.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        if value is not None:
            if hasattr(value, 'value'):  # Enum
                setattr(policy, field, value.value)
            else:
                setattr(policy, field, value)

    db.commit()
    db.refresh(policy)

    # Increment config version
    policy_engine.increment_config_version()

    logger.info(f"Policy updated: {policy.name}")

    return PolicyResponse(
        id=policy.id,
        name=policy.name,
        description=policy.description,
        src_role=policy.src_role,
        dst_role=policy.dst_role,
        port=policy.port,
        protocol=policy.protocol,
        action=policy.action,
        priority=policy.priority,
        enabled=policy.enabled,
        created_at=policy.created_at,
        updated_at=policy.updated_at
    )


@router.delete(
    "/policies/{policy_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    responses={
        204: {"description": "Policy deleted"},
        404: {"description": "Policy not found", "model": ErrorResponse},
    },
    summary="Delete policy",
    description="Delete a policy"
)
async def delete_policy(
    policy_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Delete a policy"""
    policy = db.query(AccessPolicy).filter(AccessPolicy.id == policy_id).first()

    if not policy:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Policy with id {policy_id} not found",
                "error_code": "POLICY_NOT_FOUND"
            }
        )

    db.delete(policy)
    db.commit()

    # Increment config version
    policy_engine.increment_config_version()

    logger.info(f"Policy deleted: id={policy_id}")

    return None


# === Network Info Endpoints ===

@router.get(
    "/network/stats",
    summary="Get network statistics",
    description="Get IP allocation and network statistics"
)
async def get_network_stats(
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Get network statistics"""
    return ipam_service.get_allocation_stats(db)


@router.get(
    "/network/allocations",
    summary="Get IP allocations",
    description="Get list of all IP allocations"
)
async def get_ip_allocations(
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Get all IP allocations"""
    allocations = ipam_service.get_used_ips(db)

    return {
        "allocations": [
            {"ip": ip, "hostname": hostname}
            for ip, hostname in allocations
        ],
        "total": len(allocations)
    }