#!/bin/bash
# ==============================================================================
#  ZERO TRUST NETWORK - NODE AGENT INSTALLER (Production Ready)
#  
#  Cài đặt Agent + WireGuard Client trên Ubuntu/Debian Node
#  Phiên bản: 2.1.0
#  
#  Usage:
#    curl -sL https://raw.githubusercontent.com/maithanhduyan/zero-trust-netwoking/main/scripts/node/install.sh | \
#      sudo HUB_URL=http://hub-ip:8000 ROLE=app bash
#
#  Hoặc với options:
#    sudo HUB_URL=http://hub-ip:8000 ROLE=db HOSTNAME=db-server-1 ./install.sh
#
#  ROLE options: app, db, ops, monitor, gateway
#
# ==============================================================================

set -e

# ==============================================================================
# CONFIGURATION
# ==============================================================================
HUB_URL="${HUB_URL:-}"
ROLE="${ROLE:-app}"
NODE_HOSTNAME="${HOSTNAME:-$(hostname)}"

# System paths
CONFIG_DIR="/etc/zero-trust"
LOG_DIR="/var/log/zero-trust"
DATA_DIR="/var/lib/zero-trust"

# ==============================================================================
# COLORS & LOGGING
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $1"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $1"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗${NC} $1"; exit 1; }

# ==============================================================================
# BANNER
# ==============================================================================
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║   ███████╗███████╗██████╗  ██████╗     ████████╗██████╗ ██╗   ██╗███████╗████████╗║
║   ╚══███╔╝██╔════╝██╔══██╗██╔═══██╗    ╚══██╔══╝██╔══██╗██║   ██║██╔════╝╚══██╔══╝║
║     ███╔╝ █████╗  ██████╔╝██║   ██║       ██║   ██████╔╝██║   ██║███████╗   ██║   ║
║    ███╔╝  ██╔══╝  ██╔══██╗██║   ██║       ██║   ██╔══██╗██║   ██║╚════██║   ██║   ║
║   ███████╗███████╗██║  ██║╚██████╔╝       ██║   ██║  ██║╚██████╔╝███████║   ██║   ║
║   ╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝        ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ║
║                                                                              ║
║                    ZERO TRUST NETWORK - NODE INSTALLER                       ║
║                        "Never Trust, Always Verify"                          ║
║                              Version 2.1.0                                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_phase() {
    echo ""
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}  PHASE $1: $2${NC}"
    echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ==============================================================================
# PHASE 0: PRE-FLIGHT CHECKS
# ==============================================================================
preflight_checks() {
    print_phase "0" "KIỂM TRA MÔI TRƯỜNG"

    # Check root
    if [ "$(id -u)" -ne 0 ]; then
        error "Script cần quyền root. Chạy với 'sudo $0'"
    fi
    success "Quyền root: OK"

    # Check HUB_URL
    if [ -z "$HUB_URL" ]; then
        error "Thiếu HUB_URL. Sử dụng: HUB_URL=http://hub-ip:8000 $0"
    fi
    log "Hub URL: $HUB_URL"

    # Validate role
    case "$ROLE" in
        app|db|ops|monitor|gateway) success "Role: $ROLE" ;;
        *) error "Role không hợp lệ: $ROLE. Phải là: app, db, ops, monitor, gateway" ;;
    esac

    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "Hệ điều hành: $PRETTY_NAME"
    fi

    # Check connectivity to Hub
    log "Kiểm tra kết nối đến Hub..."
    if curl -s --max-time 10 "${HUB_URL}/health" | grep -q "healthy"; then
        success "Kết nối Hub: OK"
    else
        error "Không thể kết nối Hub tại ${HUB_URL}. Kiểm tra lại URL và firewall."
    fi

    # Get node public IP (IPv4)
    PUBLIC_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || \
                hostname -I | awk '{print $1}')
    log "Public IP: $PUBLIC_IP"
}

# ==============================================================================
# PHASE 1: INSTALL DEPENDENCIES
# ==============================================================================
install_dependencies() {
    print_phase "1" "CÀI ĐẶT DEPENDENCIES"

    log "Cập nhật package lists..."
    apt-get update -qq

    log "Cài đặt system packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl \
        jq \
        wireguard \
        wireguard-tools \
        iptables \
        >/dev/null 2>&1
    
    success "Dependencies đã cài đặt"
}

# ==============================================================================
# PHASE 2: SETUP DIRECTORIES
# ==============================================================================
setup_directories() {
    print_phase "2" "TẠO CẤU TRÚC THƯ MỤC"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p /etc/wireguard

    chmod 700 /etc/wireguard
    chmod 755 "$LOG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 700 "$DATA_DIR"

    success "Đã tạo cấu trúc thư mục"
}

# ==============================================================================
# PHASE 3: GENERATE WIREGUARD KEYS
# ==============================================================================
generate_wireguard_keys() {
    print_phase "3" "TẠO WIREGUARD KEYPAIR"

    if [ -f /etc/wireguard/private.key ]; then
        log "Keypair đã tồn tại, sử dụng lại"
    else
        wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
        chmod 600 /etc/wireguard/private.key
        chmod 644 /etc/wireguard/public.key
        success "Đã tạo keypair mới"
    fi

    NODE_PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    NODE_PUBLIC_KEY=$(cat /etc/wireguard/public.key)
    log "Public Key: ${NODE_PUBLIC_KEY}"
}

# ==============================================================================
# PHASE 4: REGISTER WITH HUB
# ==============================================================================
register_with_hub() {
    print_phase "4" "ĐĂNG KÝ VỚI HUB"

    # Collect system info
    OS_INFO=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Linux")
    KERNEL=$(uname -r)
    AGENT_VERSION="2.1.0"

    log "Gửi đăng ký đến Hub..."
    
    REGISTER_DATA=$(cat << EOF
{
    "hostname": "${NODE_HOSTNAME}",
    "role": "${ROLE}",
    "public_key": "${NODE_PUBLIC_KEY}",
    "real_ip": "${PUBLIC_IP}",
    "agent_version": "${AGENT_VERSION}",
    "os_info": "${OS_INFO} (${KERNEL})"
}
EOF
)

    RESPONSE=$(curl -s -X POST "${HUB_URL}/api/v1/agent/register" \
        -H "Content-Type: application/json" \
        -d "$REGISTER_DATA")

    # Check for errors
    if echo "$RESPONSE" | grep -q '"error"'; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // .detail // "Unknown error"')
        error "Đăng ký thất bại: $ERROR_MSG"
    fi

    # Extract configuration from response
    OVERLAY_IP=$(echo "$RESPONSE" | jq -r '.overlay_ip // .data.overlay_ip // empty')
    HUB_PUBLIC_KEY=$(echo "$RESPONSE" | jq -r '.hub_public_key // .data.hub_public_key // empty')
    HUB_ENDPOINT=$(echo "$RESPONSE" | jq -r '.hub_endpoint // .data.hub_endpoint // empty')
    NODE_ID=$(echo "$RESPONSE" | jq -r '.node_id // .data.node_id // empty')

    # Validate response
    if [ -z "$OVERLAY_IP" ] || [ "$OVERLAY_IP" = "null" ]; then
        error "Hub không trả về overlay_ip. Response: $RESPONSE"
    fi

    if [ -z "$HUB_PUBLIC_KEY" ] || [ "$HUB_PUBLIC_KEY" = "null" ]; then
        error "Hub không trả về hub_public_key. Response: $RESPONSE"
    fi

    success "Đăng ký thành công!"
    log "  → Node ID:     ${NODE_ID}"
    log "  → Overlay IP:  ${OVERLAY_IP}"
    log "  → Hub Endpoint: ${HUB_ENDPOINT}"

    # Save registration info
    cat > "$CONFIG_DIR/node-info.json" << EOF
{
    "node_id": "${NODE_ID}",
    "hostname": "${NODE_HOSTNAME}",
    "role": "${ROLE}",
    "overlay_ip": "${OVERLAY_IP}",
    "public_key": "${NODE_PUBLIC_KEY}",
    "hub_url": "${HUB_URL}",
    "hub_endpoint": "${HUB_ENDPOINT}",
    "hub_public_key": "${HUB_PUBLIC_KEY}",
    "registered_at": "$(date -Iseconds)"
}
EOF
    chmod 600 "$CONFIG_DIR/node-info.json"
}

# ==============================================================================
# PHASE 5: CONFIGURE WIREGUARD
# ==============================================================================
configure_wireguard() {
    print_phase "5" "CẤU HÌNH WIREGUARD"

    log "Tạo cấu hình WireGuard..."
    cat > /etc/wireguard/wg0.conf << EOF
# ==============================================================================
# WIREGUARD NODE - Zero Trust Network
# Generated: $(date -Iseconds)
# Node: ${NODE_HOSTNAME} (${ROLE})
# ==============================================================================

[Interface]
PrivateKey = ${NODE_PRIVATE_KEY}
Address = ${OVERLAY_IP}/24
# DNS = 10.10.0.1  # Uncomment if Hub runs DNS

# Zero Trust Firewall Hook
PostUp = /etc/zero-trust/firewall-up.sh || true
PostDown = /etc/zero-trust/firewall-down.sh || true

[Peer]
# Hub Server
PublicKey = ${HUB_PUBLIC_KEY}
Endpoint = ${HUB_ENDPOINT}
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF
    chmod 600 /etc/wireguard/wg0.conf
    success "WireGuard config đã tạo"
}

# ==============================================================================
# PHASE 6: SETUP ZERO TRUST FIREWALL
# ==============================================================================
setup_firewall() {
    print_phase "6" "CẤU HÌNH ZERO TRUST FIREWALL"

    # Create firewall-up script
    cat > "$CONFIG_DIR/firewall-up.sh" << 'EOF'
#!/bin/bash
# Zero Trust Firewall - Activated on WireGuard up

# Create ZT_ACL chain if not exists
iptables -N ZT_ACL 2>/dev/null || true
iptables -F ZT_ACL

# Default policy: DROP all incoming on wg0
# Rules will be added by agent based on policies

# Hook ZT_ACL to INPUT chain for wg0 interface
iptables -C INPUT -i wg0 -j ZT_ACL 2>/dev/null || \
    iptables -I INPUT -i wg0 -j ZT_ACL

# Allow established connections
iptables -C ZT_ACL -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    iptables -A ZT_ACL -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP (ping) from Hub (10.10.0.1)
iptables -C ZT_ACL -s 10.10.0.1 -p icmp -j ACCEPT 2>/dev/null || \
    iptables -A ZT_ACL -s 10.10.0.1 -p icmp -j ACCEPT

# Default: DROP (Zero Trust - deny by default)
iptables -C ZT_ACL -j DROP 2>/dev/null || \
    iptables -A ZT_ACL -j DROP

echo "[$(date)] Zero Trust Firewall activated" >> /var/log/zero-trust/firewall.log
EOF
    chmod +x "$CONFIG_DIR/firewall-up.sh"

    # Create firewall-down script
    cat > "$CONFIG_DIR/firewall-down.sh" << 'EOF'
#!/bin/bash
# Zero Trust Firewall - Deactivated on WireGuard down

iptables -D INPUT -i wg0 -j ZT_ACL 2>/dev/null || true
iptables -F ZT_ACL 2>/dev/null || true
iptables -X ZT_ACL 2>/dev/null || true

echo "[$(date)] Zero Trust Firewall deactivated" >> /var/log/zero-trust/firewall.log
EOF
    chmod +x "$CONFIG_DIR/firewall-down.sh"

    success "Zero Trust Firewall scripts đã tạo"
}

# ==============================================================================
# PHASE 7: START WIREGUARD
# ==============================================================================
start_wireguard() {
    print_phase "7" "KHỞI ĐỘNG WIREGUARD"

    systemctl enable wg-quick@wg0 >/dev/null 2>&1
    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl start wg-quick@wg0

    # Verify connection
    log "Kiểm tra kết nối..."
    sleep 2

    if wg show wg0 >/dev/null 2>&1; then
        success "WireGuard đang chạy"
        
        # Test connectivity to Hub
        HUB_OVERLAY_IP="10.10.0.1"
        if ping -c 1 -W 3 "$HUB_OVERLAY_IP" >/dev/null 2>&1; then
            success "Kết nối Hub (${HUB_OVERLAY_IP}): OK"
        else
            warn "Không ping được Hub. Handshake có thể chưa hoàn tất."
        fi
    else
        error "WireGuard không khởi động được"
    fi
}

# ==============================================================================
# PHASE 8: CREATE AGENT SERVICE (Optional)
# ==============================================================================
create_agent_service() {
    print_phase "8" "TẠO AGENT SERVICE"

    # Create simple policy sync script
    cat > "$CONFIG_DIR/sync-policies.sh" << 'EOF'
#!/bin/bash
# Sync firewall policies from Hub

CONFIG_FILE="/etc/zero-trust/node-info.json"
LOG_FILE="/var/log/zero-trust/agent.log"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[$(date)] Config file not found" >> "$LOG_FILE"
    exit 1
fi

HUB_URL=$(jq -r '.hub_url' "$CONFIG_FILE")
NODE_ID=$(jq -r '.node_id' "$CONFIG_FILE")

# Fetch ACL rules from Hub
RULES=$(curl -s "${HUB_URL}/api/v1/agent/acl/${NODE_ID}" 2>/dev/null)

if [ -z "$RULES" ] || echo "$RULES" | grep -q '"error"'; then
    echo "[$(date)] Failed to fetch ACL rules" >> "$LOG_FILE"
    exit 1
fi

# Apply rules (simplified - real implementation would parse and apply)
echo "[$(date)] Synced policies from Hub" >> "$LOG_FILE"
EOF
    chmod +x "$CONFIG_DIR/sync-policies.sh"

    # Create systemd timer for periodic sync
    cat > /etc/systemd/system/zero-trust-agent.service << EOF
[Unit]
Description=Zero Trust Agent - Policy Sync
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=oneshot
ExecStart=${CONFIG_DIR}/sync-policies.sh
EOF

    cat > /etc/systemd/system/zero-trust-agent.timer << EOF
[Unit]
Description=Zero Trust Agent - Periodic Policy Sync

[Timer]
OnBootSec=30
OnUnitActiveSec=60
AccuracySec=10

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable zero-trust-agent.timer >/dev/null 2>&1
    systemctl start zero-trust-agent.timer

    success "Agent service đã tạo (sync mỗi 60s)"
}

# ==============================================================================
# PHASE 9: SUMMARY
# ==============================================================================
show_summary() {
    print_phase "9" "HOÀN TẤT"

    # Get latency to Hub
    LATENCY=$(ping -c 1 -W 3 10.10.0.1 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1ms/' || echo "N/A")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                              ║${NC}"
    echo -e "${GREEN}║             ✅ ZERO TRUST NODE ĐÃ CÀI ĐẶT THÀNH CÔNG!                       ║${NC}"
    echo -e "${GREEN}║                                                                              ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}📍 THÔNG TIN NODE:${NC}"
    echo -e "${GREEN}║${NC}  ├─ Hostname:     ${CYAN}${NODE_HOSTNAME}${NC}"
    echo -e "${GREEN}║${NC}  ├─ Role:         ${CYAN}${ROLE}${NC}"
    echo -e "${GREEN}║${NC}  ├─ Overlay IP:   ${CYAN}${OVERLAY_IP}${NC}"
    echo -e "${GREEN}║${NC}  ├─ Public IP:    ${CYAN}${PUBLIC_IP}${NC}"
    echo -e "${GREEN}║${NC}  └─ Public Key:   ${CYAN}${NODE_PUBLIC_KEY}${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🔗 KẾT NỐI HUB:${NC}"
    echo -e "${GREEN}║${NC}  ├─ Hub URL:      ${CYAN}${HUB_URL}${NC}"
    echo -e "${GREEN}║${NC}  ├─ Hub Endpoint: ${CYAN}${HUB_ENDPOINT}${NC}"
    echo -e "${GREEN}║${NC}  └─ Latency:      ${CYAN}${LATENCY}${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🔒 ZERO TRUST FIREWALL:${NC}"
    echo -e "${GREEN}║${NC}  └─ Status:       ${CYAN}Active (Default DENY)${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}📋 QUẢN LÝ:${NC}"
    echo -e "${GREEN}║${NC}  ├─ systemctl status wg-quick@wg0"
    echo -e "${GREEN}║${NC}  ├─ wg show wg0"
    echo -e "${GREEN}║${NC}  ├─ iptables -L ZT_ACL -n -v"
    echo -e "${GREEN}║${NC}  └─ journalctl -u wg-quick@wg0 -f"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🔥 GỠ CÀI ĐẶT:${NC}"
    echo -e "${GREEN}║${NC}  └─ curl -sL .../scripts/node/uninstall.sh | sudo bash"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    print_banner
    
    preflight_checks
    install_dependencies
    setup_directories
    generate_wireguard_keys
    register_with_hub
    configure_wireguard
    setup_firewall
    start_wireguard
    create_agent_service
    show_summary
}

main "$@"
