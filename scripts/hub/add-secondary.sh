#!/bin/bash
# ==============================================================================
# ZERO TRUST NETWORK - ADD SECONDARY HUB (High Availability)
# Setup Active-Passive failover with 2 Hubs
# ==============================================================================
#
# Usage:
#   On Secondary Hub server:
#   sudo ./add-hub.sh --primary-ip=5.104.82.252 --primary-key=hM7m0p...
#
# How it works:
#   1. Secondary Hub syncs WireGuard config from Primary
#   2. Secondary Hub runs Control Plane in read-only/sync mode
#   3. Nodes are configured with both Hub endpoints
#   4. WireGuard automatically fails over when Primary is unreachable
#
# Failover time: ~25-30 seconds (based on PersistentKeepalive)
#
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Parse arguments
PRIMARY_IP=""
PRIMARY_KEY=""
SYNC_INTERVAL=60

for arg in "$@"; do
    case $arg in
        --primary-ip=*) PRIMARY_IP="${arg#*=}" ;;
        --primary-key=*) PRIMARY_KEY="${arg#*=}" ;;
        --sync-interval=*) SYNC_INTERVAL="${arg#*=}" ;;
    esac
done

# Banner
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          ZERO TRUST - SECONDARY HUB SETUP (HA Mode)                  ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║                                                                      ║${NC}"
echo -e "${CYAN}║   Architecture: Active-Passive Failover                              ║${NC}"
echo -e "${CYAN}║                                                                      ║${NC}"
echo -e "${CYAN}║   ┌─────────────┐         ┌─────────────┐                           ║${NC}"
echo -e "${CYAN}║   │ Primary Hub │◄───────►│Secondary Hub│                           ║${NC}"
echo -e "${CYAN}║   │  (Active)   │  Sync   │  (Standby)  │                           ║${NC}"
echo -e "${CYAN}║   └──────┬──────┘         └──────┬──────┘                           ║${NC}"
echo -e "${CYAN}║          │                       │                                   ║${NC}"
echo -e "${CYAN}║          └───────────┬───────────┘                                   ║${NC}"
echo -e "${CYAN}║                      │                                               ║${NC}"
echo -e "${CYAN}║              ┌───────┴───────┐                                       ║${NC}"
echo -e "${CYAN}║              │    Nodes      │                                       ║${NC}"
echo -e "${CYAN}║              │ (connect both)│                                       ║${NC}"
echo -e "${CYAN}║              └───────────────┘                                       ║${NC}"
echo -e "${CYAN}║                                                                      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Validate
if [ -z "$PRIMARY_IP" ]; then
    error "Thiếu --primary-ip. Ví dụ: --primary-ip=5.104.82.252"
fi

if [ -z "$PRIMARY_KEY" ]; then
    error "Thiếu --primary-key. Lấy từ Primary Hub: cat /etc/wireguard/public.key"
fi

# Check root
if [ "$EUID" -ne 0 ]; then
    error "Script phải chạy với quyền root"
fi

log "Cấu hình:"
echo "  Primary Hub IP:    $PRIMARY_IP"
echo "  Primary Public Key: ${PRIMARY_KEY:0:20}..."
echo "  Sync Interval:     ${SYNC_INTERVAL}s"
echo ""

# ==============================================================================
# PHASE 1: INSTALL DEPENDENCIES
# ==============================================================================
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} PHASE 1: CÀI ĐẶT DEPENDENCIES${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

# Install WireGuard
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools curl git

# Enable IP forwarding
cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-wireguard.conf >/dev/null 2>&1

success "Dependencies đã sẵn sàng"

# ==============================================================================
# PHASE 2: GENERATE WIREGUARD KEYS
# ==============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} PHASE 2: TẠO WIREGUARD KEYS${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

if [ ! -f /etc/wireguard/private.key ]; then
    wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
    chmod 600 /etc/wireguard/private.key
    success "Đã tạo keypair mới"
else
    success "Keypair đã tồn tại"
fi

SECONDARY_PRIVATE_KEY=$(cat /etc/wireguard/private.key)
SECONDARY_PUBLIC_KEY=$(cat /etc/wireguard/public.key)
log "Secondary Hub Public Key: $SECONDARY_PUBLIC_KEY"

# Get public IP
SECONDARY_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo "REPLACE_ME")
log "Secondary Hub IP: $SECONDARY_IP"

# ==============================================================================
# PHASE 3: CONFIGURE WIREGUARD (Secondary Hub)
# ==============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} PHASE 3: CẤU HÌNH WIREGUARD${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

# Secondary Hub uses 10.10.0.254 as its overlay IP
cat > /etc/wireguard/wg0.conf << EOF
# ==============================================================================
# WIREGUARD SECONDARY HUB CONFIGURATION
# HA Mode: Active-Passive
# Generated: $(date -Iseconds)
# ==============================================================================

[Interface]
Address = 10.10.0.254/24
PrivateKey = ${SECONDARY_PRIVATE_KEY}
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE

# Primary Hub - Sync peer config
[Peer]
PublicKey = ${PRIMARY_KEY}
Endpoint = ${PRIMARY_IP}:51820
AllowedIPs = 10.10.0.1/32
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf
success "Đã tạo WireGuard config"

# ==============================================================================
# PHASE 4: CREATE SYNC SERVICE
# ==============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} PHASE 4: TẠO SYNC SERVICE${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

# Create sync script
cat > /usr/local/bin/zt-hub-sync.sh << 'SYNCEOF'
#!/bin/bash
# Sync peers from Primary Hub to Secondary Hub
# Runs periodically to keep peer list in sync

PRIMARY_API="http://PRIMARY_IP_PLACEHOLDER:8000"
LOG_FILE="/var/log/zerotrust/hub-sync.log"

mkdir -p /var/log/zerotrust

log() {
    echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Get peers from Primary Hub API
PEERS=$(curl -s "${PRIMARY_API}/api/v1/admin/wireguard/peers" 2>/dev/null)

if [ -z "$PEERS" ]; then
    log "ERROR: Cannot reach Primary Hub API"
    exit 1
fi

# Parse and add each peer (skip Primary Hub peer)
echo "$PEERS" | jq -r '.peers[] | select(.allowed_ips != "10.10.0.1/32") | "\(.public_key) \(.allowed_ips)"' 2>/dev/null | while read -r pubkey allowed_ips; do
    if [ -n "$pubkey" ] && [ -n "$allowed_ips" ]; then
        # Check if peer exists
        if ! wg show wg0 peers | grep -q "$pubkey"; then
            wg set wg0 peer "$pubkey" allowed-ips "$allowed_ips"
            log "Added peer: $pubkey -> $allowed_ips"
        fi
    fi
done

log "Sync completed"
SYNCEOF

# Replace placeholder
sed -i "s|PRIMARY_IP_PLACEHOLDER|${PRIMARY_IP}|g" /usr/local/bin/zt-hub-sync.sh
chmod +x /usr/local/bin/zt-hub-sync.sh

# Create systemd timer for periodic sync
cat > /etc/systemd/system/zt-hub-sync.service << EOF
[Unit]
Description=Zero Trust Hub Sync Service
After=network.target wg-quick@wg0.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zt-hub-sync.sh
EOF

cat > /etc/systemd/system/zt-hub-sync.timer << EOF
[Unit]
Description=Zero Trust Hub Sync Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=${SYNC_INTERVAL}
AccuracySec=5

[Install]
WantedBy=timers.target
EOF

success "Đã tạo sync service"

# ==============================================================================
# PHASE 5: START SERVICES
# ==============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN} PHASE 5: KHỞI ĐỘNG SERVICES${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Start sync timer
systemctl daemon-reload
systemctl enable zt-hub-sync.timer
systemctl start zt-hub-sync.timer

sleep 2

if wg show wg0 &>/dev/null; then
    success "WireGuard đang chạy"
    wg show wg0 | head -10
else
    error "WireGuard không khởi động được"
fi

# ==============================================================================
# PHASE 6: INSTRUCTIONS
# ==============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ SECONDARY HUB ĐÃ CÀI ĐẶT!                            ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                                      ║${NC}"
echo -e "${GREEN}║${NC}  Secondary Hub:"
echo -e "${GREEN}║${NC}    IP:         ${YELLOW}${SECONDARY_IP}${NC}"
echo -e "${GREEN}║${NC}    Overlay IP: ${YELLOW}10.10.0.254${NC}"
echo -e "${GREEN}║${NC}    Public Key: ${YELLOW}${SECONDARY_PUBLIC_KEY}${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}  ${YELLOW}⚠️  BƯỚC TIẾP THEO:${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  1. Trên PRIMARY HUB, thêm Secondary làm peer:"
echo -e "${GREEN}║${NC}     ${CYAN}wg set wg0 peer ${SECONDARY_PUBLIC_KEY} \\${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}    allowed-ips 10.10.0.254/32 \\${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}    endpoint ${SECONDARY_IP}:51820${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}wg-quick save wg0${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  2. Cập nhật nodes để kết nối cả 2 Hubs:"
echo -e "${GREEN}║${NC}     Trong /etc/wireguard/wg0.conf, thêm peer thứ 2:"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}[Peer]${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}# Secondary Hub${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}PublicKey = ${SECONDARY_PUBLIC_KEY}${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}Endpoint = ${SECONDARY_IP}:51820${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}AllowedIPs = 10.10.0.254/32${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}PersistentKeepalive = 25${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  3. Hoặc chạy script update trên mỗi node:"
echo -e "${GREEN}║${NC}     ${CYAN}curl -sL .../scripts/node/add-failover.sh | \\${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}  SECONDARY_IP=${SECONDARY_IP} \\${NC}"
echo -e "${GREEN}║${NC}     ${CYAN}  SECONDARY_KEY=${SECONDARY_PUBLIC_KEY} bash${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
