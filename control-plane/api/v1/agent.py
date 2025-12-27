# control-plane/api/v1/agent.py
"""
Agent API Endpoints
RESTful API for Zero Trust Agents to register, sync config, and heartbeat
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
from datetime import datetime
from typing import Optional
import logging

from database.session import get_db
from database.models import Node, NodeStatus
from schemas.node import (
    NodeCreate,
    NodeResponse,
    NodeRegistrationResponse,
    NodeStatus as SchemaNodeStatus
)
from schemas.config import (
    AgentConfig,
    HeartbeatRequest,
    HeartbeatResponse,
    PeerConfig,
)
from schemas.policy import FirewallRule
from schemas.base import BaseResponse, ErrorResponse
from core.node_manager import node_manager
from core.policy_engine import policy_engine
from core.ipam import ipam_service
from core.trust_engine import trust_engine
from config import settings

logger = logging.getLogger(__name__)

router = APIRouter()


# === Registration Endpoints ===

@router.post(
    "/register",
    response_model=NodeRegistrationResponse,
    status_code=status.HTTP_201_CREATED,
    responses={
        201: {"description": "Node registered successfully"},
        200: {"description": "Node already registered (re-registration)"},
        400: {"description": "Invalid request data", "model": ErrorResponse},
        409: {"description": "Hostname already exists", "model": ErrorResponse},
        503: {"description": "IP pool exhausted", "model": ErrorResponse},
    },
    summary="Register a new node",
    description="""
    Register a new node in the Zero Trust network.

    **Flow:**
    1. Agent generates WireGuard keypair
    2. Agent sends public key, hostname, and role
    3. Control Plane allocates Overlay IP
    4. Control Plane returns config for WireGuard setup

    **Re-registration:**
    If a node with the same public key already exists, it will be treated as
    a re-registration (e.g., after reboot) and existing config will be returned.
    """
)
async def register_node(
    node_in: NodeCreate,
    request: Request,
    db: Session = Depends(get_db)
):
    """Register a new Agent node"""
    client_ip = request.client.host if request.client else None
    logger.info(f"Registration request from {client_ip}: {node_in.hostname}")

    try:
        node, is_new = node_manager.register_node(
            db=db,
            hostname=node_in.hostname,
            role=node_in.role.value,
            public_key=node_in.public_key,
            description=node_in.description,
            agent_version=node_in.agent_version,
            os_info=node_in.os_info,
            client_ip=client_ip
        )

        response = NodeRegistrationResponse(
            node_id=node.id,
            hostname=node.hostname,
            status=SchemaNodeStatus(node.status),
            overlay_ip=node.overlay_ip,
            hub_public_key=settings.HUB_PUBLIC_KEY,
            hub_endpoint=settings.HUB_ENDPOINT,
            dns_servers=settings.DNS_SERVERS,
            allowed_ips=settings.OVERLAY_NETWORK,
            message="Registration successful" if is_new else "Re-registration successful"
        )

        # Return 200 for re-registration, 201 for new
        if not is_new:
            return response
        return response

    except ValueError as e:
        logger.warning(f"Registration failed for {node_in.hostname}: {e}")
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": str(e),
                "error_code": "HOSTNAME_EXISTS"
            }
        )
    except RuntimeError as e:
        logger.error(f"IP allocation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "error": str(e),
                "error_code": "IP_POOL_EXHAUSTED"
            }
        )


# === Configuration Endpoints ===

@router.get(
    "/config",
    response_model=AgentConfig,
    responses={
        200: {"description": "Configuration retrieved successfully"},
        403: {"description": "Node not approved", "model": ErrorResponse},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Get Agent configuration",
    description="""
    Retrieve the current configuration for an Agent.

    Agent should poll this endpoint periodically to:
    1. Get updated ACL rules
    2. Get updated peer list
    3. Detect configuration changes

    **Authentication:**
    Node is identified by public_key query parameter.
    """
)
async def get_agent_config(
    public_key: str,
    request: Request,
    db: Session = Depends(get_db)
):
    """Get configuration for an Agent"""
    node = node_manager.get_node_by_public_key(db, public_key)

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": "Node not found",
                "error_code": "NODE_NOT_FOUND"
            }
        )

    if node.status != NodeStatus.ACTIVE.value:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": f"Node status is '{node.status}'. Must be 'active' to get config.",
                "error_code": "NODE_NOT_ACTIVE",
                "status": node.status
            }
        )

    # Update heartbeat
    client_ip = request.client.host if request.client else None
    node_manager.update_heartbeat(db, node, client_ip)

    # Build configuration
    config_data = policy_engine.build_config_for_node(db, node)

    # Convert ACL rules to schema
    acl_rules = [
        FirewallRule(
            src_ip=rule["src_ip"],
            port=rule["port"],
            proto=rule["proto"],
            action=rule["action"],
            comment=rule.get("comment")
        )
        for rule in config_data["acl_rules"]
    ]

    # Convert peers to schema
    peers = [
        PeerConfig(
            public_key=peer["public_key"],
            allowed_ips=peer["allowed_ips"],
            endpoint=peer.get("endpoint"),
            persistent_keepalive=peer.get("persistent_keepalive", 25)
        )
        for peer in config_data["peers"]
    ]

    return AgentConfig(
        node_id=node.id,
        hostname=node.hostname,
        role=node.role,
        status=node.status,
        overlay_ip=node.overlay_ip,
        hub_public_key=settings.HUB_PUBLIC_KEY,
        hub_endpoint=settings.HUB_ENDPOINT,
        peers=peers,
        acl_rules=acl_rules,
        config_version=node.config_version,
        next_sync_seconds=settings.CONFIG_SYNC_INTERVAL
    )


@router.get(
    "/config/{hostname}",
    response_model=AgentConfig,
    responses={
        200: {"description": "Configuration retrieved successfully"},
        403: {"description": "Node not approved", "model": ErrorResponse},
        404: {"description": "Node not found", "model": ErrorResponse},
    },
    summary="Get Agent configuration by hostname",
    description="Alternative endpoint to get config using hostname instead of public_key"
)
async def get_agent_config_by_hostname(
    hostname: str,
    request: Request,
    db: Session = Depends(get_db)
):
    """Get configuration for an Agent by hostname"""
    node = node_manager.get_node_by_hostname(db, hostname)

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Node '{hostname}' not found",
                "error_code": "NODE_NOT_FOUND"
            }
        )

    if node.status != NodeStatus.ACTIVE.value:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": f"Node status is '{node.status}'. Must be 'active' to get config.",
                "error_code": "NODE_NOT_ACTIVE",
                "status": node.status
            }
        )

    # Update heartbeat
    client_ip = request.client.host if request.client else None
    node_manager.update_heartbeat(db, node, client_ip)

    # Build configuration
    config_data = policy_engine.build_config_for_node(db, node)

    # Convert ACL rules
    acl_rules = [
        FirewallRule(
            src_ip=rule["src_ip"],
            port=rule["port"],
            proto=rule["proto"],
            action=rule["action"],
            comment=rule.get("comment")
        )
        for rule in config_data["acl_rules"]
    ]

    # Convert peers
    peers = [
        PeerConfig(
            public_key=peer["public_key"],
            allowed_ips=peer["allowed_ips"],
            endpoint=peer.get("endpoint"),
            persistent_keepalive=peer.get("persistent_keepalive", 25)
        )
        for peer in config_data["peers"]
    ]

    return AgentConfig(
        node_id=node.id,
        hostname=node.hostname,
        role=node.role,
        status=node.status,
        overlay_ip=node.overlay_ip,
        hub_public_key=settings.HUB_PUBLIC_KEY,
        hub_endpoint=settings.HUB_ENDPOINT,
        peers=peers,
        acl_rules=acl_rules,
        config_version=node.config_version,
        next_sync_seconds=settings.CONFIG_SYNC_INTERVAL
    )


# === Heartbeat Endpoints ===

@router.post(
    "/heartbeat",
    response_model=HeartbeatResponse,
    summary="Node heartbeat",
    description="Agent sends periodic heartbeat to report status"
)
async def heartbeat(
    heartbeat_in: HeartbeatRequest,
    request: Request,
    db: Session = Depends(get_db)
):
    """Process heartbeat from Agent with trust calculation"""
    node = node_manager.get_node_by_public_key(db, heartbeat_in.public_key)

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": "Node not found",
                "error_code": "NODE_NOT_FOUND"
            }
        )

    # Update heartbeat info
    client_ip = request.client.host if request.client else None
    node_manager.update_heartbeat(
        db,
        node,
        client_ip,
        heartbeat_in.agent_version
    )

    # Build metrics for trust calculation
    metrics = {
        "cpu_percent": heartbeat_in.cpu_percent or 0,
        "memory_percent": heartbeat_in.memory_percent or 0,
        "disk_percent": heartbeat_in.disk_percent or 0,
        "security_events": heartbeat_in.security_events or {},
        "network_stats": heartbeat_in.network_stats or {}
    }

    # Calculate and update trust score
    trust_score = node.trust_score or 1.0
    risk_level = node.risk_level or "low"
    action_taken = "none"

    try:
        trust_score, action_taken = trust_engine.update_node_trust(
            db=db,
            node=node,
            metrics=metrics,
            record_history=True
        )
        risk_level = node.risk_level or "low"

        # Log significant trust events
        if action_taken != 'none':
            logger.warning(
                f"Trust action for {node.hostname}: {action_taken} "
                f"(score: {trust_score:.2f}, risk: {risk_level})"
            )

    except Exception as e:
        logger.error(f"Trust calculation failed for {node.hostname}: {e}")

    # Check if config has changed
    config_changed = False  # TODO: Implement config change detection

    return HeartbeatResponse(
        status="ok",
        config_changed=config_changed,
        current_config_version=node.config_version,
        message=f"Heartbeat received from {node.hostname}",
        trust_score=trust_score,
        risk_level=risk_level,
        action_taken=action_taken if action_taken != 'none' else None
    )


@router.post(
    "/heartbeat/{hostname}",
    response_model=HeartbeatResponse,
    summary="Node heartbeat by hostname",
    description="Alternative heartbeat endpoint using hostname"
)
async def heartbeat_by_hostname(
    hostname: str,
    request: Request,
    db: Session = Depends(get_db)
):
    """Process heartbeat by hostname"""
    node = node_manager.get_node_by_hostname(db, hostname)

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Node '{hostname}' not found",
                "error_code": "NODE_NOT_FOUND"
            }
        )

    # Update heartbeat
    client_ip = request.client.host if request.client else None
    node_manager.update_heartbeat(db, node, client_ip)

    return HeartbeatResponse(
        status="ok",
        config_changed=False,
        current_config_version=node.config_version,
        message=f"Heartbeat received from {hostname}"
    )


# === Status Endpoints ===

@router.get(
    "/status/{hostname}",
    response_model=NodeResponse,
    summary="Get node status",
    description="Get current status of a node"
)
async def get_node_status(
    hostname: str,
    db: Session = Depends(get_db)
):
    """Get node status by hostname"""
    node = node_manager.get_node_by_hostname(db, hostname)

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": f"Node '{hostname}' not found",
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