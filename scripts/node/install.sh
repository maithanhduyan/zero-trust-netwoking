#!/bin/bash
# ==============================================================================
#  ZERO TRUST AGENT - AUTOMATED INSTALLER
#  Cài đặt Agent trên các node (app servers, database servers, etc.)
# ==============================================================================
#
#  Usage:
#    # Từ Hub server, copy command này sang node cần cài:
#    curl -sL https://raw.githubusercontent.com/maithanhduyan/zero-trust-netwoking/main/scripts/install-agent.sh | \
#      sudo HUB_URL="http://<HUB_IP>:8000" \
#           HUB_ENDPOINT="<HUB_IP>:51820" \
#           HUB_PUBLIC_KEY="<HUB_PUBLIC_KEY>" \
#           NODE_ROLE="app" \
#           bash
#
#    # Hoặc download và chạy:
#    chmod +x install-agent.sh
#    sudo HUB_URL="http://203.0.113.1:8000" \
#         HUB_ENDPOINT="203.0.113.1:51820" \
#         HUB_PUBLIC_KEY="hM7m0pKxxdQzkwREnS3KM9tSK0LBTFlGq+xMSKptRSI=" \
#         NODE_ROLE="db" \
#         ./install-agent.sh
#
# ==============================================================================

set -e

# --- CẤU HÌNH ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/zero-trust-agent}"
REPO_URL="https://github.com/maithanhduyan/zero-trust-netwoking.git"
BRANCH="${BRANCH:-master}"

# Required environment variables (must be set by user)
HUB_URL="${HUB_URL:-}"
HUB_ENDPOINT="${HUB_ENDPOINT:-}"
HUB_PUBLIC_KEY="${HUB_PUBLIC_KEY:-}"
HUB_ADMIN_TOKEN="${HUB_ADMIN_TOKEN:-change-me-admin-secret}"
NODE_ROLE="${NODE_ROLE:-app}"
NODE_HOSTNAME_RAW="${NODE_HOSTNAME:-$(hostname)}"
SYNC_INTERVAL="${SYNC_INTERVAL:-60}"

# Sanitize hostname: lowercase, replace dots with hyphens, remove invalid chars
NODE_HOSTNAME=$(echo "$NODE_HOSTNAME_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/\./-/g' | sed 's/[^a-z0-9-]//g' | sed 's/^-//;s/-$//' | cut -c1-63)

# WireGuard config
WG_PORT="51820"
WG_NETWORK="10.10.0.0/24"

# --- MÀU SẮC ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# --- HELPER FUNCTIONS ---
log()     { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════════════╗
║                                                                                    ║
║   ███████╗███████╗██████╗  ██████╗     ████████╗██████╗ ██╗   ██╗███████╗████████╗ ║
║   ╚══███╔╝██╔════╝██╔══██╗██╔═══██╗    ╚══██╔══╝██╔══██╗██║   ██║██╔════╝╚══██╔══╝ ║
║     ███╔╝ █████╗  ██████╔╝██║   ██║       ██║   ██████╔╝██║   ██║███████╗   ██║    ║
║    ███╔╝  ██╔══╝  ██╔══██╗██║   ██║       ██║   ██╔══██╗██║   ██║╚════██║   ██║    ║
║   ███████╗███████╗██║  ██║╚██████╔╝       ██║   ██║  ██║╚██████╔╝███████║   ██║    ║
║   ╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝        ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝    ║
║                                                                                    ║
║                    ZERO TRUST AGENT INSTALLER                                      ║
║                    "Never Trust, Always Verify"                                    ║
╚════════════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_phase() {
    echo ""
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA} PHASE $1: $2${NC}"
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════════${NC}"
}

# ==============================================================================
# PHASE 0: VALIDATE REQUIREMENTS
# ==============================================================================
validate_requirements() {
    print_phase "0" "KIỂM TRA YÊU CẦU"

    # Check root
    if [ "$(id -u)" -ne 0 ]; then
        error "Script này cần quyền root. Vui lòng chạy với 'sudo'."
    fi
    success "Đang chạy với quyền root"

    # Check required environment variables
    if [ -z "$HUB_URL" ]; then
        error "HUB_URL chưa được đặt. Ví dụ: HUB_URL='http://hub.example.com:8000'"
    fi

    if [ -z "$HUB_ENDPOINT" ]; then
        error "HUB_ENDPOINT chưa được đặt. Ví dụ: HUB_ENDPOINT='203.0.113.1:51820'"
    fi

    if [ -z "$HUB_PUBLIC_KEY" ]; then
        error "HUB_PUBLIC_KEY chưa được đặt. Lấy từ Hub: cat /etc/wireguard/public.key"
    fi

    log "Cấu hình:"
    echo "  HUB_URL:        $HUB_URL"
    echo "  HUB_ENDPOINT:   $HUB_ENDPOINT"
    echo "  HUB_PUBLIC_KEY: ${HUB_PUBLIC_KEY:0:20}..."
    echo "  NODE_ROLE:      $NODE_ROLE"
    if [ "$NODE_HOSTNAME" != "$NODE_HOSTNAME_RAW" ]; then
        echo "  NODE_HOSTNAME:  $NODE_HOSTNAME (sanitized from: $NODE_HOSTNAME_RAW)"
    else
        echo "  NODE_HOSTNAME:  $NODE_HOSTNAME"
    fi

    success "Cấu hình hợp lệ"

    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "Hệ điều hành: $PRETTY_NAME"
    fi
}

# ==============================================================================
# PHASE 1: INSTALL DEPENDENCIES
# ==============================================================================
install_dependencies() {
    print_phase "1" "CÀI ĐẶT DEPENDENCIES"

    # Update package list
    log "Cập nhật package list..."
    apt-get update -qq

    # Install base packages
    log "Cài đặt các gói cơ bản..."
    apt-get install -y -qq curl git openssl ca-certificates iptables python3 python3-pip python3-venv >/dev/null 2>&1
    success "Các gói cơ bản đã sẵn sàng"

    # Install WireGuard
    log "Kiểm tra WireGuard..."
    if ! command -v wg &> /dev/null; then
        log "Đang cài đặt WireGuard..."
        apt-get install -y -qq wireguard wireguard-tools >/dev/null 2>&1
    fi
    success "WireGuard đã sẵn sàng"

    # Enable IP forwarding
    log "Cấu hình sysctl..."
    cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward = 1
EOF
    sysctl -p /etc/sysctl.d/99-wireguard.conf >/dev/null 2>&1
    success "Sysctl đã cấu hình"
}

# ==============================================================================
# PHASE 2: GENERATE WIREGUARD KEYS
# ==============================================================================
setup_wireguard_keys() {
    print_phase "2" "TẠO WIREGUARD KEYPAIR"

    # Create WireGuard directory
    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard

    # Generate keys if not exists
    if [ ! -f /etc/wireguard/private.key ]; then
        log "Đang tạo keypair..."
        wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
        chmod 600 /etc/wireguard/private.key
        success "Đã tạo keypair mới"
    else
        success "Keypair đã tồn tại"
    fi

    # Read public key for registration
    NODE_PUBLIC_KEY=$(cat /etc/wireguard/public.key)
    log "Public Key: $NODE_PUBLIC_KEY"
}

# ==============================================================================
# PHASE 3: DOWNLOAD AGENT CODE
# ==============================================================================
download_agent() {
    print_phase "3" "TẢI MÃ NGUỒN AGENT"

    # Clone or update repository
    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Cập nhật mã nguồn..."
        cd "$INSTALL_DIR"
        git fetch origin
        git reset --hard "origin/$BRANCH"
    else
        log "Clone repository..."
        rm -rf "$INSTALL_DIR"
        git clone -b "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
    fi

    success "Mã nguồn tại: $INSTALL_DIR"
}

# ==============================================================================
# PHASE 4: REGISTER WITH CONTROL PLANE
# ==============================================================================
register_with_hub() {
    print_phase "4" "ĐĂNG KÝ VỚI CONTROL PLANE"

    NODE_PUBLIC_KEY=$(cat /etc/wireguard/public.key)
    OS_INFO=$(. /etc/os-release && echo "$PRETTY_NAME ($(uname -m))")

    log "Đăng ký node với Control Plane..."

    REGISTER_RESPONSE=$(curl -s -X POST "${HUB_URL}/api/v1/agent/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"hostname\": \"${NODE_HOSTNAME}\",
            \"role\": \"${NODE_ROLE}\",
            \"public_key\": \"${NODE_PUBLIC_KEY}\",
            \"description\": \"Installed via install-agent.sh\",
            \"agent_version\": \"1.0.0\",
            \"os_info\": \"${OS_INFO}\"
        }" 2>&1)

    # Check response
    if echo "$REGISTER_RESPONSE" | grep -q "overlay_ip"; then
        OVERLAY_IP=$(echo "$REGISTER_RESPONSE" | grep -o '"overlay_ip":"[^"]*"' | cut -d'"' -f4)
        NODE_STATUS=$(echo "$REGISTER_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

        success "Đăng ký thành công!"
        echo "  Overlay IP: $OVERLAY_IP"
        echo "  Status:     $NODE_STATUS"

        # Save overlay IP for WireGuard config
        echo "$OVERLAY_IP" > /etc/wireguard/overlay_ip
    else
        warn "Phản hồi từ Control Plane:"
        echo "$REGISTER_RESPONSE" | head -5

        # Try to extract error message
        if echo "$REGISTER_RESPONSE" | grep -q "error"; then
            warn "Có thể đã đăng ký trước đó. Tiếp tục..."
        fi
    fi
}

# ==============================================================================
# PHASE 5: CONFIGURE WIREGUARD
# ==============================================================================
configure_wireguard() {
    print_phase "5" "CẤU HÌNH WIREGUARD"

    WG_PRIVATE_KEY=$(cat /etc/wireguard/private.key)

    # Get overlay IP from registration or file
    if [ -f /etc/wireguard/overlay_ip ]; then
        OVERLAY_IP=$(cat /etc/wireguard/overlay_ip)
    else
        # Fallback: request new IP from Control Plane via node lookup
        warn "Overlay IP chưa được gán. Sử dụng IP tạm: 10.10.0.100"
        OVERLAY_IP="10.10.0.100"
    fi

    # Ensure IP has CIDR notation
    if [[ "$OVERLAY_IP" != */* ]]; then
        OVERLAY_IP="${OVERLAY_IP}/24"
    fi

    log "Overlay IP: $OVERLAY_IP"

    # Create WireGuard config
    log "Tạo cấu hình WireGuard..."
    cat > /etc/wireguard/wg0.conf << EOF
# ==============================================================================
# WIREGUARD SPOKE CONFIGURATION
# Node: ${NODE_HOSTNAME} (${NODE_ROLE})
# Generated by install-agent.sh - $(date -Iseconds)
# ==============================================================================

[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = ${OVERLAY_IP}

[Peer]
# Hub Server
PublicKey = ${HUB_PUBLIC_KEY}
Endpoint = ${HUB_ENDPOINT}
AllowedIPs = ${WG_NETWORK}
PersistentKeepalive = 25
EOF
    chmod 600 /etc/wireguard/wg0.conf

    # Start WireGuard
    log "Khởi động WireGuard..."
    systemctl enable wg-quick@wg0 >/dev/null 2>&1
    systemctl restart wg-quick@wg0 || systemctl start wg-quick@wg0

    # Verify
    sleep 2
    if wg show wg0 >/dev/null 2>&1; then
        success "WireGuard đang chạy"
        wg show wg0 | head -10
    else
        warn "WireGuard chưa khởi động. Kiểm tra: journalctl -u wg-quick@wg0"
    fi
}

# ==============================================================================
# PHASE 6: ADD PEER TO HUB (via API)
# ==============================================================================
add_peer_to_hub() {
    print_phase "6" "TỰ ĐỘNG THÊM PEER VÀO HUB"

    NODE_PUBLIC_KEY=$(cat /etc/wireguard/public.key)

    # Get overlay IP (just the IP, not CIDR)
    if [ -f /etc/wireguard/overlay_ip ]; then
        OVERLAY_IP_CIDR=$(cat /etc/wireguard/overlay_ip)
        OVERLAY_IP_ONLY=$(echo "$OVERLAY_IP_CIDR" | cut -d'/' -f1)
    else
        OVERLAY_IP_ONLY="10.10.0.100"
    fi

    log "Gọi API thêm peer vào Hub..."
    log "Node Public Key: $NODE_PUBLIC_KEY"
    log "AllowedIPs: ${OVERLAY_IP_ONLY}/32"

    # Call API to add peer to Hub
    ADD_PEER_RESPONSE=$(curl -s -X POST "${HUB_URL}/api/v1/admin/wireguard/add-peer" \
        -H "Content-Type: application/json" \
        -H "X-Admin-Token: ${HUB_ADMIN_TOKEN}" \
        -d "{
            \"public_key\": \"${NODE_PUBLIC_KEY}\",
            \"allowed_ips\": \"${OVERLAY_IP_ONLY}/32\",
            \"comment\": \"${NODE_HOSTNAME}\"
        }" 2>&1)

    if echo "$ADD_PEER_RESPONSE" | grep -q '"success":true'; then
        success "✅ Peer đã được thêm vào Hub tự động!"
    else
        warn "Không thể tự động thêm peer. Phản hồi: $ADD_PEER_RESPONSE"
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}  FALLBACK: Chạy lệnh sau trên HUB SERVER:${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "wg set wg0 peer ${NODE_PUBLIC_KEY} allowed-ips ${OVERLAY_IP_ONLY}/32"
        echo "wg-quick save wg0"
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

# ==============================================================================
# PHASE 7: SETUP AGENT SERVICE
# ==============================================================================
setup_agent_service() {
    print_phase "7" "CÀI ĐẶT AGENT SERVICE"

    cd "$INSTALL_DIR/agent"

    # Create virtual environment
    log "Tạo Python virtual environment..."
    python3 -m venv venv

    # Install dependencies
    log "Cài đặt Python packages..."
    venv/bin/pip install --quiet --upgrade pip
    venv/bin/pip install --quiet requests schedule psutil pyyaml
    success "Dependencies đã cài đặt"

    # Create agent config
    log "Tạo cấu hình Agent..."
    mkdir -p /etc/zerotrust
    cat > /etc/zerotrust/agent.conf << EOF
# ==============================================================================
# ZERO TRUST AGENT CONFIGURATION
# Generated by install-agent.sh - $(date -Iseconds)
# ==============================================================================

[agent]
hostname = ${NODE_HOSTNAME}
role = ${NODE_ROLE}
control_plane_url = ${HUB_URL}
sync_interval = ${SYNC_INTERVAL}
heartbeat_interval = 30

[wireguard]
interface = wg0
config_dir = /etc/wireguard

[firewall]
backend = iptables
chain_name = ZT_ACL

[logging]
level = INFO
file = /var/log/zerotrust/agent.log
EOF

    # Create log directory
    mkdir -p /var/log/zerotrust

    # Create systemd service
    log "Tạo systemd service..."
    cat > /etc/systemd/system/zero-trust-agent.service << EOF
[Unit]
Description=Zero Trust Agent
After=network.target wg-quick@wg0.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/agent
ExecStart=${INSTALL_DIR}/agent/venv/bin/python agent.py --hostname ${NODE_HOSTNAME} --role ${NODE_ROLE} --control-plane ${HUB_URL} --sync-interval ${SYNC_INTERVAL}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload and start
    systemctl daemon-reload
    systemctl enable zero-trust-agent
    systemctl restart zero-trust-agent

    # Wait and check
    sleep 3
    if systemctl is-active --quiet zero-trust-agent; then
        success "Agent service đang chạy"
    else
        warn "Agent chưa khởi động. Kiểm tra: journalctl -u zero-trust-agent -f"
    fi
}

# ==============================================================================
# PHASE 8: VERIFY & SHOW SUMMARY
# ==============================================================================
show_summary() {
    print_phase "8" "HOÀN TẤT"

    # Get info
    NODE_PUBLIC_KEY=$(cat /etc/wireguard/public.key 2>/dev/null || echo "N/A")
    OVERLAY_IP=$(cat /etc/wireguard/overlay_ip 2>/dev/null || echo "N/A")
    WG_STATUS=$(wg show wg0 2>/dev/null | grep -E "peer|endpoint" | head -4 || echo "Not connected")
    AGENT_STATUS=$(systemctl is-active zero-trust-agent 2>/dev/null || echo "unknown")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✅ ZERO TRUST AGENT ĐÃ CÀI ĐẶT!                         ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                                      ║${NC}"
    echo -e "${GREEN}║${NC}  🖥️  Node:          ${YELLOW}${NODE_HOSTNAME}${NC} (${NODE_ROLE})"
    echo -e "${GREEN}║${NC}  🌍 Overlay IP:    ${YELLOW}${OVERLAY_IP}${NC}"
    echo -e "${GREEN}║${NC}  🔑 Public Key:    ${YELLOW}${NODE_PUBLIC_KEY}${NC}"
    echo -e "${GREEN}║${NC}  🔗 Hub:           ${YELLOW}${HUB_ENDPOINT}${NC}"
    echo -e "${GREEN}║${NC}  📂 Install Dir:   ${YELLOW}${INSTALL_DIR}${NC}"
    echo -e "${GREEN}║                                                                      ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  Agent Status: ${AGENT_STATUS}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}COMMANDS:${NC}"
    echo -e "${GREEN}║${NC}  - Agent logs:     journalctl -u zero-trust-agent -f"
    echo -e "${GREEN}║${NC}  - WireGuard:      wg show wg0"
    echo -e "${GREEN}║${NC}  - Restart agent:  systemctl restart zero-trust-agent"
    echo -e "${GREEN}║${NC}  - Test VPN:       ping 10.10.0.1"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Test connectivity
    log "Kiểm tra kết nối tới Hub..."
    sleep 2
    if ping -c 2 -W 3 10.10.0.1 >/dev/null 2>&1; then
        success "✅ Kết nối tới Hub thành công!"
    else
        warn "⚠️ Chưa ping được Hub (10.10.0.1). Đã thêm peer vào Hub chưa?"
        echo "  → Xem PHASE 6 để biết lệnh cần chạy trên Hub"
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    print_banner

    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ZERO TRUST AGENT INSTALLER v1.0${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo ""

    validate_requirements
    install_dependencies
    setup_wireguard_keys
    download_agent
    register_with_hub
    configure_wireguard
    add_peer_to_hub
    setup_agent_service
    show_summary
}

# Run
main "$@"
