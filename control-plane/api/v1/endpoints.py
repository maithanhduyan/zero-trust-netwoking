# control-plane/api/v1/endpoints.py
"""
Legacy API Endpoints (for backward compatibility)
New code should use agent.py and admin.py
"""

from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session
import logging

from database.session import get_db
from database.models import Node, NodeStatus
from schemas.node import NodeCreate, NodeResponse
from schemas.config import WireGuardConfig, PeerConfig
from schemas.policy import FirewallRule
from core.node_manager import node_manager, SERVER_PUBLIC_KEY, SERVER_ENDPOINT
from core.policy_engine import policy_engine

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post(
    "/register",
    response_model=NodeResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new node (Legacy)",
    description="Legacy endpoint. Use /agent/register instead.",
    deprecated=True
)
async def register(
    node: NodeCreate,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Legacy registration endpoint
    Agent gọi endpoint này lần đầu để lấy Overlay IP
    """
    client_ip = request.client.host if request.client else None

    try:
        registered_node, is_new = node_manager.register_node(
            db=db,
            hostname=node.hostname,
            role=node.role.value if hasattr(node.role, 'value') else node.role,
            public_key=node.public_key,
            client_ip=client_ip
        )

        return NodeResponse(
            id=registered_node.id,
            hostname=registered_node.hostname,
            role=registered_node.role,
            status=registered_node.status,
            overlay_ip=registered_node.overlay_ip,
            real_ip=registered_node.real_ip,
            public_key=registered_node.public_key,
            description=registered_node.description,
            agent_version=registered_node.agent_version,
            os_info=registered_node.os_info,
            last_seen=registered_node.last_seen,
            created_at=registered_node.created_at,
            updated_at=registered_node.updated_at
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(e)
        )
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e)
        )


@router.get(
    "/config/{hostname}",
    response_model=WireGuardConfig,
    summary="Get WireGuard configuration (Legacy)",
    description="Legacy endpoint. Use /agent/config/{hostname} instead.",
    deprecated=True
)
async def get_config(
    hostname: str,
    request: Request,
    db: Session = Depends(get_db)
):
    """
    Legacy config endpoint
    Agent gọi endpoint này định kỳ để:
    1. Cập nhật Real IP (Heartbeat)
    2. Lấy danh sách ACL mới nhất
    """
    node = db.query(Node).filter(Node.hostname == hostname).first()

    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Node not found"
        )

    if node.status != NodeStatus.ACTIVE.value:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Node not approved. Status: {node.status}"
        )

    # 1. Update Heartbeat & Real IP
    node.real_ip = request.client.host if request.client else None
    node.last_seen = datetime.utcnow()
    db.commit()

    # 2. Tính toán ACL Rules dựa trên Role
    config_data = policy_engine.build_config_for_node(db, node)
    acl_rules = [
        FirewallRule(
            src_ip=rule["src_ip"],
            port=rule["port"],
            proto=rule["proto"],
            action=rule["action"]
        )
        for rule in config_data["acl_rules"]
    ]

    # 3. Trả về cấu hình
    from schemas.config import InterfaceConfig

    return WireGuardConfig(
        interface=InterfaceConfig(
            address=node.overlay_ip,
            dns=["10.0.0.1"]
        ),
        peers=[
            PeerConfig(
                public_key=SERVER_PUBLIC_KEY,
                allowed_ips="10.0.0.0/24",
                endpoint=SERVER_ENDPOINT,
                persistent_keepalive=25
            )
        ],
        config_version=node.config_version,
        generated_at=datetime.utcnow()
    )