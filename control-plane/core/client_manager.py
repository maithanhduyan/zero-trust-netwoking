# control-plane/core/client_manager.py
"""
Client Device Manager
Handles registration, configuration generation, and lifecycle management
for mobile/laptop VPN clients
"""

import logging
import secrets
import subprocess
import base64
import io
from datetime import datetime, timedelta
from typing import Optional, List, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import and_

from database.models import ClientDevice, NodeStatus, DeviceType, TunnelMode, IPAllocation
from config import settings

logger = logging.getLogger(__name__)


class ClientManager:
    """
    Manages client device lifecycle for Zero Trust VPN access

    Features:
    - Server-side key generation (clients don't need to generate keys)
    - QR code generation for mobile WireGuard apps
    - Config expiration and rotation
    - Multi-device per user support with limits
    """

    def __init__(self):
        self.overlay_network = settings.OVERLAY_NETWORK
        self.hub_public_key = settings.HUB_PUBLIC_KEY
        self.hub_endpoint = settings.HUB_ENDPOINT
        self.dns_servers = settings.DNS_SERVERS

    def generate_wireguard_keypair(self) -> Tuple[str, str]:
        """
        Generate WireGuard private/public key pair using wg command
        Returns: (private_key, public_key)
        """
        try:
            # Generate private key
            private_key = subprocess.run(
                ["wg", "genkey"],
                capture_output=True,
                text=True,
                check=True
            ).stdout.strip()

            # Derive public key
            public_key = subprocess.run(
                ["wg", "pubkey"],
                input=private_key,
                capture_output=True,
                text=True,
                check=True
            ).stdout.strip()

            return private_key, public_key

        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to generate WireGuard keys: {e}")
            raise RuntimeError("Failed to generate WireGuard keys. Is WireGuard installed?")
        except FileNotFoundError:
            logger.error("WireGuard 'wg' command not found")
            raise RuntimeError("WireGuard tools not installed. Please install wireguard-tools.")

    def allocate_client_ip(self, db: Session) -> str:
        """
        Allocate an overlay IP for a client device
        Uses a separate pool from server nodes (.100 - .250)
        """
        network_prefix = ".".join(settings.OVERLAY_GATEWAY.split(".")[:-1])

        # Find existing client IPs
        existing_ips = db.query(ClientDevice.overlay_ip).filter(
            ClientDevice.status != NodeStatus.REVOKED.value
        ).all()
        existing_ips = {ip[0].split("/")[0] for ip in existing_ips if ip[0]}

        # Find first available IP in client pool
        for i in range(settings.CLIENT_IP_POOL_START, settings.CLIENT_IP_POOL_END + 1):
            candidate_ip = f"{network_prefix}.{i}"
            if candidate_ip not in existing_ips:
                return f"{candidate_ip}/24"

        raise RuntimeError("No available IP addresses in client pool")

    def create_device(
        self,
        db: Session,
        device_name: str,
        device_type: str = DeviceType.MOBILE.value,
        user_id: Optional[str] = None,
        tunnel_mode: str = TunnelMode.FULL.value,
        expires_days: int = None,
        description: Optional[str] = None
    ) -> ClientDevice:
        """
        Create a new client device with generated keys and config
        """
        # Check device limit per user
        if user_id:
            user_device_count = db.query(ClientDevice).filter(
                and_(
                    ClientDevice.user_id == user_id,
                    ClientDevice.status != NodeStatus.REVOKED.value
                )
            ).count()

            if user_device_count >= settings.CLIENT_MAX_DEVICES_PER_USER:
                raise ValueError(
                    f"User {user_id} has reached maximum device limit "
                    f"({settings.CLIENT_MAX_DEVICES_PER_USER})"
                )

        # Check for duplicate device name for same user
        existing = db.query(ClientDevice).filter(
            and_(
                ClientDevice.device_name == device_name,
                ClientDevice.user_id == user_id,
                ClientDevice.status != NodeStatus.REVOKED.value
            )
        ).first()

        if existing:
            raise ValueError(f"Device '{device_name}' already exists for this user")

        # Generate WireGuard keys
        private_key, public_key = self.generate_wireguard_keypair()

        # Allocate overlay IP
        overlay_ip = self.allocate_client_ip(db)

        # Generate config download token
        config_token = secrets.token_urlsafe(32)

        # Calculate expiration
        if expires_days is None:
            expires_days = settings.CLIENT_DEFAULT_EXPIRES_DAYS
        expires_at = datetime.utcnow() + timedelta(days=expires_days)

        # Generate optional preshared key for extra security
        psk = subprocess.run(
            ["wg", "genpsk"],
            capture_output=True,
            text=True,
            check=True
        ).stdout.strip()

        # Create device record
        device = ClientDevice(
            device_name=device_name,
            device_type=device_type,
            user_id=user_id,
            description=description,
            public_key=public_key,
            private_key_encrypted=private_key,  # TODO: Encrypt in production
            preshared_key=psk,
            overlay_ip=overlay_ip,
            tunnel_mode=tunnel_mode,
            status=NodeStatus.ACTIVE.value if not settings.CLIENT_REQUIRE_ADMIN_APPROVAL else NodeStatus.PENDING.value,
            config_token=config_token,
            expires_at=expires_at
        )

        db.add(device)
        db.commit()
        db.refresh(device)

        logger.info(f"Created client device: {device_name} ({device_type}) for user {user_id}, IP: {overlay_ip}")

        return device

    def generate_wireguard_config(self, device: ClientDevice) -> str:
        """
        Generate complete WireGuard config file content for a client device
        """
        # Determine AllowedIPs based on tunnel mode
        if device.tunnel_mode == TunnelMode.FULL.value:
            # Full tunnel: route all traffic through VPN
            allowed_ips = "0.0.0.0/0, ::/0"
        else:
            # Split tunnel: only route overlay network
            allowed_ips = self.overlay_network

        # Build config
        config_lines = [
            "[Interface]",
            f"PrivateKey = {device.private_key_encrypted}",
            f"Address = {device.overlay_ip}",
            f"DNS = {', '.join(self.dns_servers)}",
            f"MTU = 1420",
            "",
            "[Peer]",
            f"PublicKey = {self.hub_public_key}",
            f"Endpoint = {self.hub_endpoint}",
            f"AllowedIPs = {allowed_ips}",
            f"PersistentKeepalive = 25",
        ]

        # Add preshared key if present
        if device.preshared_key:
            config_lines.insert(-1, f"PresharedKey = {device.preshared_key}")

        return "\n".join(config_lines)

    def generate_qr_code(self, config_text: str) -> Optional[str]:
        """
        Generate QR code from WireGuard config
        Returns base64-encoded PNG image
        """
        try:
            import qrcode
            from PIL import Image

            # Create QR code
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_L,
                box_size=10,
                border=4,
            )
            qr.add_data(config_text)
            qr.make(fit=True)

            # Create image
            img = qr.make_image(fill_color="black", back_color="white")

            # Convert to base64
            buffer = io.BytesIO()
            img.save(buffer, format="PNG")
            buffer.seek(0)

            return base64.b64encode(buffer.getvalue()).decode("utf-8")

        except ImportError:
            logger.warning("qrcode or PIL not installed. QR code generation disabled.")
            return None
        except Exception as e:
            logger.error(f"Failed to generate QR code: {e}")
            return None

    def get_device(self, db: Session, device_id: int) -> Optional[ClientDevice]:
        """Get a device by ID"""
        return db.query(ClientDevice).filter(ClientDevice.id == device_id).first()

    def get_device_by_token(self, db: Session, token: str) -> Optional[ClientDevice]:
        """Get a device by config download token"""
        return db.query(ClientDevice).filter(
            and_(
                ClientDevice.config_token == token,
                ClientDevice.status == NodeStatus.ACTIVE.value
            )
        ).first()

    def list_devices(
        self,
        db: Session,
        user_id: Optional[str] = None,
        status: Optional[str] = None,
        include_expired: bool = False
    ) -> List[ClientDevice]:
        """List client devices with optional filtering"""
        query = db.query(ClientDevice)

        if user_id:
            query = query.filter(ClientDevice.user_id == user_id)

        if status:
            query = query.filter(ClientDevice.status == status)

        if not include_expired:
            query = query.filter(ClientDevice.expires_at > datetime.utcnow())

        return query.order_by(ClientDevice.created_at.desc()).all()

    def revoke_device(self, db: Session, device_id: int) -> bool:
        """Revoke a client device"""
        device = self.get_device(db, device_id)
        if not device:
            return False

        device.status = NodeStatus.REVOKED.value
        device.config_token = None  # Invalidate download token
        db.commit()

        logger.info(f"Revoked client device: {device.device_name} (ID: {device_id})")

        # TODO: Remove peer from Hub WireGuard interface

        return True

    def mark_config_downloaded(self, db: Session, device_id: int):
        """Mark that config has been downloaded (clear token for security)"""
        device = self.get_device(db, device_id)
        if device:
            device.config_downloaded = True
            # Optionally clear token after first download
            # device.config_token = None
            db.commit()

    def get_active_client_peers(self, db: Session) -> List[dict]:
        """
        Get all active client devices as WireGuard peers
        Used by Hub to add client peers to wg0.conf
        """
        devices = db.query(ClientDevice).filter(
            and_(
                ClientDevice.status == NodeStatus.ACTIVE.value,
                ClientDevice.expires_at > datetime.utcnow()
            )
        ).all()

        peers = []
        for device in devices:
            peer = {
                "public_key": device.public_key,
                "allowed_ips": device.overlay_ip.replace("/24", "/32"),  # Single IP for client
                "preshared_key": device.preshared_key,
                "comment": f"# Client: {device.device_name} ({device.user_id or 'anonymous'})"
            }
            peers.append(peer)

        return peers


# Singleton instance
client_manager = ClientManager()
