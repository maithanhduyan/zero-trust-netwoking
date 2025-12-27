# control-plane/api/v1/client.py
"""
Client Device API Endpoints
RESTful API for managing mobile/laptop VPN client devices
"""

from fastapi import APIRouter, Depends, HTTPException, Header, Query, status
from fastapi.responses import PlainTextResponse
from sqlalchemy.orm import Session
from typing import Optional
import logging

from database.session import get_db
from database.models import ClientDevice, NodeStatus
from schemas.node import (
    ClientDeviceCreate,
    ClientDeviceResponse,
    ClientDeviceListResponse,
    ClientConfigResponse,
    DeviceType,
    TunnelMode,
)
from schemas.base import BaseResponse
from core.client_manager import client_manager
from core.wireguard_service import wireguard_service
from config import settings

logger = logging.getLogger(__name__)

router = APIRouter()


# === Authentication Dependency ===

async def verify_admin_token(x_admin_token: str = Header(..., alias="X-Admin-Token")):
    """Verify admin authentication token"""
    if x_admin_token != settings.ADMIN_SECRET:
        logger.warning("Invalid admin token attempt for client API")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "Invalid or missing admin token", "error_code": "UNAUTHORIZED"}
        )
    return True


# === Client Device Endpoints ===

@router.post(
    "/devices",
    response_model=ClientDeviceResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register new client device",
    description="Create a new client device (mobile/laptop) for VPN access. Returns config download token."
)
async def create_client_device(
    device: ClientDeviceCreate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """
    Register a new client device for VPN access

    - Generates WireGuard keypair server-side
    - Allocates overlay IP from client pool
    - Returns token to download WireGuard config
    """
    try:
        new_device = client_manager.create_device(
            db=db,
            device_name=device.device_name,
            device_type=device.device_type.value,
            user_id=device.user_id,
            tunnel_mode=device.tunnel_mode.value,
            expires_days=device.expires_days,
            description=device.description
        )

        # Add peer to Hub WireGuard interface
        try:
            wireguard_service.add_peer(
                public_key=new_device.public_key,
                allowed_ips=new_device.overlay_ip.replace("/24", "/32"),
                preshared_key=new_device.preshared_key
            )
            logger.info(f"Added client peer to Hub: {new_device.device_name}")
        except Exception as e:
            logger.warning(f"Failed to add peer to Hub (may need manual sync): {e}")

        return ClientDeviceResponse(
            id=new_device.id,
            device_name=new_device.device_name,
            device_type=DeviceType(new_device.device_type),
            user_id=new_device.user_id,
            tunnel_mode=TunnelMode(new_device.tunnel_mode),
            status=NodeStatus(new_device.status),
            overlay_ip=new_device.overlay_ip,
            public_key=new_device.public_key,
            created_at=new_device.created_at,
            expires_at=new_device.expires_at,
            config_token=new_device.config_token
        )

    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"error": str(e), "error_code": "VALIDATION_ERROR"}
        )
    except RuntimeError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error": str(e), "error_code": "SERVER_ERROR"}
        )


@router.get(
    "/devices",
    response_model=ClientDeviceListResponse,
    summary="List client devices",
    description="Get list of all client devices with optional filtering"
)
async def list_client_devices(
    user_id: Optional[str] = Query(None, description="Filter by user ID"),
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status"),
    include_expired: bool = Query(False, description="Include expired devices"),
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """List all client devices"""
    devices = client_manager.list_devices(
        db=db,
        user_id=user_id,
        status=status_filter,
        include_expired=include_expired
    )

    return ClientDeviceListResponse(
        devices=[
            ClientDeviceResponse(
                id=d.id,
                device_name=d.device_name,
                device_type=DeviceType(d.device_type),
                user_id=d.user_id,
                tunnel_mode=TunnelMode(d.tunnel_mode),
                status=NodeStatus(d.status),
                overlay_ip=d.overlay_ip,
                public_key=d.public_key,
                created_at=d.created_at,
                expires_at=d.expires_at,
                config_token=d.config_token or ""
            )
            for d in devices
        ],
        total=len(devices)
    )


@router.get(
    "/devices/{device_id}",
    response_model=ClientDeviceResponse,
    summary="Get client device details",
    description="Get details of a specific client device"
)
async def get_client_device(
    device_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Get device details by ID"""
    device = client_manager.get_device(db, device_id)

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "Device not found", "error_code": "NOT_FOUND"}
        )

    return ClientDeviceResponse(
        id=device.id,
        device_name=device.device_name,
        device_type=DeviceType(device.device_type),
        user_id=device.user_id,
        tunnel_mode=TunnelMode(device.tunnel_mode),
        status=NodeStatus(device.status),
        overlay_ip=device.overlay_ip,
        public_key=device.public_key,
        created_at=device.created_at,
        expires_at=device.expires_at,
        config_token=device.config_token or ""
    )


@router.delete(
    "/devices/{device_id}",
    response_model=BaseResponse,
    summary="Revoke client device",
    description="Revoke a client device (removes VPN access)"
)
async def revoke_client_device(
    device_id: int,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_admin_token)
):
    """Revoke a client device"""
    device = client_manager.get_device(db, device_id)

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error": "Device not found", "error_code": "NOT_FOUND"}
        )

    # Remove peer from Hub
    try:
        wireguard_service.remove_peer(device.public_key)
        logger.info(f"Removed client peer from Hub: {device.device_name}")
    except Exception as e:
        logger.warning(f"Failed to remove peer from Hub: {e}")

    # Revoke in database
    client_manager.revoke_device(db, device_id)

    return BaseResponse(
        success=True,
        message=f"Device '{device.device_name}' has been revoked"
    )


# === Config Download Endpoints (No admin auth required - uses token) ===

@router.get(
    "/config/{token}",
    response_model=ClientConfigResponse,
    summary="Get device config by token",
    description="Download WireGuard config using one-time token. Returns config and QR code."
)
async def get_config_by_token(
    token: str,
    db: Session = Depends(get_db)
):
    """
    Get WireGuard config for a device using the config token

    This endpoint does NOT require admin authentication.
    The token acts as a one-time password.
    """
    device = client_manager.get_device_by_token(db, token)

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "error": "Invalid or expired config token",
                "error_code": "INVALID_TOKEN"
            }
        )

    # Check expiration
    if device.is_expired:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={
                "error": "Device config has expired",
                "error_code": "EXPIRED"
            }
        )

    # Generate config
    wg_config = client_manager.generate_wireguard_config(device)

    # Generate QR code
    qr_code = client_manager.generate_qr_code(wg_config)

    # Mark as downloaded
    client_manager.mark_config_downloaded(db, device.id)

    return ClientConfigResponse(
        device_name=device.device_name,
        device_type=DeviceType(device.device_type),
        tunnel_mode=TunnelMode(device.tunnel_mode),
        wireguard_config=wg_config,
        qr_code_base64=qr_code,
        overlay_ip=device.overlay_ip,
        expires_at=device.expires_at,
        hub_endpoint=settings.HUB_ENDPOINT
    )


@router.get(
    "/config/{token}/raw",
    response_class=PlainTextResponse,
    summary="Download raw WireGuard config",
    description="Download WireGuard config as plain text file"
)
async def download_raw_config(
    token: str,
    db: Session = Depends(get_db)
):
    """
    Download raw WireGuard config file

    Use this endpoint to save directly as wg0.conf
    """
    device = client_manager.get_device_by_token(db, token)

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or expired config token"
        )

    if device.is_expired:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Device config has expired"
        )

    # Generate config
    wg_config = client_manager.generate_wireguard_config(device)

    # Mark as downloaded
    client_manager.mark_config_downloaded(db, device.id)

    return PlainTextResponse(
        content=wg_config,
        media_type="text/plain",
        headers={
            "Content-Disposition": f'attachment; filename="{device.device_name}.conf"'
        }
    )


# === QR Code Endpoint ===

@router.get(
    "/config/{token}/qr",
    summary="Get QR code image",
    description="Get QR code as PNG image for scanning with mobile WireGuard app"
)
async def get_qr_code(
    token: str,
    db: Session = Depends(get_db)
):
    """Get QR code image for mobile scanning"""
    from fastapi.responses import Response
    import base64

    device = client_manager.get_device_by_token(db, token)

    if not device:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or expired config token"
        )

    if device.is_expired:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="Device config has expired"
        )

    # Generate config and QR
    wg_config = client_manager.generate_wireguard_config(device)
    qr_base64 = client_manager.generate_qr_code(wg_config)

    if not qr_base64:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="QR code generation not available. Install qrcode and Pillow packages."
        )

    # Decode base64 to bytes
    qr_bytes = base64.b64decode(qr_base64)

    return Response(
        content=qr_bytes,
        media_type="image/png",
        headers={
            "Content-Disposition": f'inline; filename="{device.device_name}-qr.png"'
        }
    )
