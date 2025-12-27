#!/bin/bash
# ==============================================================================
#  ZERO TRUST NETWORK - HUB INSTALLER (Production Ready)
#  
#  Cài đặt Control Plane + WireGuard Hub trên Ubuntu Server
#  Phiên bản: 2.1.0
#  
#  Usage:
#    curl -sL https://raw.githubusercontent.com/maithanhduyan/zero-trust-netwoking/main/scripts/hub/install.sh | sudo bash
#    
#    Hoặc với cấu hình tùy chỉnh:
#    sudo HUB_PORT=8000 WG_PORT=51820 ./install.sh
#
# ==============================================================================

set -e

# ==============================================================================
# CẤU HÌNH MẶC ĐỊNH (có thể override qua environment variables)
# ==============================================================================
INSTALL_DIR="${INSTALL_DIR:-/opt/zero-trust}"
REPO_URL="https://github.com/maithanhduyan/zero-trust-netwoking.git"
BRANCH="${BRANCH:-main}"

# Network Configuration
WG_OVERLAY_NETWORK="${WG_OVERLAY_NETWORK:-10.10.0.0/24}"
WG_HUB_IP="${WG_HUB_IP:-10.10.0.1}"
WG_PORT="${WG_PORT:-51820}"
HUB_API_PORT="${HUB_API_PORT:-8000}"

# System Configuration
LOG_DIR="/var/log/zero-trust"
CONFIG_DIR="/etc/zero-trust"
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
╔════════════════════════════════════════════════════════════════════════════════╗
║                                                                                ║
║   ███████╗███████╗██████╗  ██████╗     ████████╗██████╗ ██╗   ██╗███████╗████████╗║
║   ╚══███╔╝██╔════╝██╔══██╗██╔═══██╗    ╚══██╔══╝██╔══██╗██║   ██║██╔════╝╚══██╔══╝║
║     ███╔╝ █████╗  ██████╔╝██║   ██║       ██║   ██████╔╝██║   ██║███████╗   ██║   ║
║    ███╔╝  ██╔══╝  ██╔══██╗██║   ██║       ██║   ██╔══██╗██║   ██║╚════██║   ██║   ║
║   ███████╗███████╗██║  ██║╚██████╔╝       ██║   ██║  ██║╚██████╔╝███████║   ██║   ║
║   ╚══════╝╚══════╝╚═╝  ╚═╝ ╚═════╝        ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ║
║                                                                                ║
║                    ZERO TRUST NETWORK - HUB INSTALLER                          ║
║                        "Never Trust, Always Verify"                            ║
║                              Version 2.1.0                                     ║
╚════════════════════════════════════════════════════════════════════════════════╝
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

    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "Hệ điều hành: $PRETTY_NAME"
        
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            warn "Script được thiết kế cho Ubuntu/Debian. Có thể không hoạt động đúng trên $ID"
        fi
    fi

    # Check architecture
    ARCH=$(uname -m)
    log "Kiến trúc: $ARCH"
    
    # Check memory
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_MEM" -lt 512 ]; then
        warn "RAM thấp ($TOTAL_MEM MB). Khuyến nghị tối thiểu 1GB"
    else
        success "RAM: ${TOTAL_MEM}MB"
    fi

    # Check disk space
    FREE_DISK=$(df -m /opt 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    if [ "$FREE_DISK" -lt 1024 ]; then
        warn "Dung lượng trống thấp (${FREE_DISK}MB). Khuyến nghị tối thiểu 2GB"
    else
        success "Disk: ${FREE_DISK}MB khả dụng"
    fi

    # Detect public IP (IPv4 only)
    PUBLIC_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || \
                curl -4 -s --max-time 5 api.ipify.org 2>/dev/null || \
                hostname -I | awk '{print $1}')
    
    if [ -z "$PUBLIC_IP" ]; then
        error "Không thể xác định IP public"
    fi
    success "IP Public: $PUBLIC_IP"

    # Get default interface
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    log "Network interface: $DEFAULT_IFACE"
}

# ==============================================================================
# PHASE 1: INSTALL SYSTEM DEPENDENCIES
# ==============================================================================
install_dependencies() {
    print_phase "1" "CÀI ĐẶT DEPENDENCIES"

    log "Cập nhật package lists..."
    apt-get update -qq

    log "Cài đặt system packages..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        curl \
        git \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release \
        jq \
        wireguard \
        wireguard-tools \
        python3 \
        python3-pip \
        python3-venv \
        >/dev/null 2>&1
    
    success "System packages đã cài đặt"

    # Install uv (fast Python package manager)
    if ! command -v uv &> /dev/null; then
        log "Cài đặt uv (Python package manager)..."
        curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
        export PATH="$HOME/.local/bin:$PATH"
        success "uv đã cài đặt"
    else
        success "uv đã có sẵn"
    fi

    # Enable IP forwarding (permanent)
    log "Bật IP forwarding..."
    cat > /etc/sysctl.d/99-zero-trust.conf << 'EOF'
# Zero Trust Network - IP Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
    sysctl -p /etc/sysctl.d/99-zero-trust.conf >/dev/null 2>&1
    success "IP forwarding đã bật"
}

# ==============================================================================
# PHASE 2: SETUP DIRECTORIES
# ==============================================================================
setup_directories() {
    print_phase "2" "TẠO CẤU TRÚC THƯ MỤC"

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p /etc/wireguard

    chmod 700 /etc/wireguard
    chmod 755 "$LOG_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 700 "$DATA_DIR"

    success "Đã tạo cấu trúc thư mục:"
    log "  → Cài đặt:  $INSTALL_DIR"
    log "  → Logs:     $LOG_DIR"
    log "  → Config:   $CONFIG_DIR"
    log "  → Data:     $DATA_DIR"
}

# ==============================================================================
# PHASE 3: SETUP WIREGUARD HUB
# ==============================================================================
setup_wireguard() {
    print_phase "3" "CẤU HÌNH WIREGUARD HUB"

    # Generate keys if not exists
    if [ ! -f /etc/wireguard/private.key ]; then
        log "Tạo keypair mới cho Hub..."
        wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
        chmod 600 /etc/wireguard/private.key
        chmod 644 /etc/wireguard/public.key
        success "Đã tạo keypair mới"
    else
        success "Keypair đã tồn tại, sử dụng lại"
    fi

    WG_PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    WG_PUBLIC_KEY=$(cat /etc/wireguard/public.key)

    log "Tạo cấu hình WireGuard Hub..."
    cat > /etc/wireguard/wg0.conf << EOF
# ==============================================================================
# WIREGUARD HUB - Zero Trust Network
# Generated: $(date -Iseconds)
# ==============================================================================

[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = ${WG_HUB_IP}/24
ListenPort = ${WG_PORT}

# Routing & NAT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE

# ==============================================================================
# PEERS - Được quản lý tự động bởi Control Plane
# ==============================================================================
EOF
    chmod 600 /etc/wireguard/wg0.conf

    log "Khởi động WireGuard..."
    systemctl enable wg-quick@wg0 >/dev/null 2>&1
    systemctl stop wg-quick@wg0 2>/dev/null || true
    systemctl start wg-quick@wg0

    if wg show wg0 >/dev/null 2>&1; then
        success "WireGuard Hub đang chạy"
        log "  → Interface: wg0"
        log "  → Address:   ${WG_HUB_IP}/24"
        log "  → Port:      ${WG_PORT}/udp"
        log "  → Public Key: ${WG_PUBLIC_KEY}"
    else
        error "Không thể khởi động WireGuard"
    fi

    echo "$WG_PUBLIC_KEY" > "$CONFIG_DIR/hub.pubkey"
    echo "$PUBLIC_IP" > "$CONFIG_DIR/hub.endpoint"
}

# ==============================================================================
# PHASE 4: INSTALL CONTROL PLANE
# ==============================================================================
install_control_plane() {
    print_phase "4" "CÀI ĐẶT CONTROL PLANE"

    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Cập nhật source code..."
        cd "$INSTALL_DIR"
        git fetch origin
        git reset --hard "origin/$BRANCH"
    else
        log "Clone repository..."
        rm -rf "$INSTALL_DIR"
        git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    fi
    cd "$INSTALL_DIR"
    success "Source code tại: $INSTALL_DIR"

    log "Tạo Python virtual environment..."
    cd "$INSTALL_DIR/control-plane"
    
    export PATH="$HOME/.local/bin:$PATH"
    
    if command -v uv &> /dev/null; then
        uv venv .venv >/dev/null 2>&1 || python3 -m venv .venv
        source .venv/bin/activate
        uv pip install -q \
            fastapi \
            "uvicorn[standard]" \
            sqlalchemy \
            pydantic \
            pydantic-settings \
            python-dotenv \
            pyyaml \
            aiofiles \
            python-multipart \
            2>/dev/null
    else
        python3 -m venv .venv
        source .venv/bin/activate
        pip install -q \
            fastapi \
            "uvicorn[standard]" \
            sqlalchemy \
            pydantic \
            pydantic-settings \
            python-dotenv \
            pyyaml \
            aiofiles \
            python-multipart
    fi
    success "Python dependencies đã cài đặt"

    # Generate secrets
    SECRET_KEY=$(openssl rand -hex 32)
    ADMIN_SECRET=$(openssl rand -hex 16)

    log "Tạo cấu hình Control Plane..."
    cat > "$INSTALL_DIR/control-plane/.env" << EOF
# ==============================================================================
# ZERO TRUST CONTROL PLANE - Configuration
# Generated: $(date -Iseconds)
# ==============================================================================

# === Server ===
HOST=0.0.0.0
PORT=${HUB_API_PORT}
DEBUG=false
LOG_LEVEL=INFO

# === Database ===
DATABASE_URL=sqlite:///${DATA_DIR}/zerotrust.db

# === WireGuard Hub ===
HUB_PUBLIC_KEY=${WG_PUBLIC_KEY}
HUB_ENDPOINT=${PUBLIC_IP}:${WG_PORT}
OVERLAY_NETWORK=${WG_OVERLAY_NETWORK}
WG_CONFIG_PATH=/etc/wireguard/wg0.conf

# === Security ===
SECRET_KEY=${SECRET_KEY}
ADMIN_SECRET=${ADMIN_SECRET}
TOKEN_EXPIRE_MINUTES=60
AGENT_TOKEN_EXPIRE_DAYS=30

# === CORS (for web dashboard) ===
CORS_ORIGINS=["http://localhost:3000","http://127.0.0.1:3000"]
EOF
    chmod 600 "$INSTALL_DIR/control-plane/.env"

    ln -sf "$INSTALL_DIR/control-plane/.env" "$CONFIG_DIR/control-plane.env"
    success "Configuration đã tạo"
}

# ==============================================================================
# PHASE 5: CREATE SYSTEMD SERVICE
# ==============================================================================
create_systemd_service() {
    print_phase "5" "TẠO SYSTEMD SERVICE"

    UVICORN_PATH="$INSTALL_DIR/control-plane/.venv/bin/uvicorn"

    cat > /etc/systemd/system/zero-trust-control-plane.service << EOF
[Unit]
Description=Zero Trust Control Plane API
Documentation=https://github.com/maithanhduyan/zero-trust-netwoking
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${INSTALL_DIR}/control-plane
Environment="PATH=${INSTALL_DIR}/control-plane/.venv/bin:/usr/local/bin:/usr/bin"
Environment="PYTHONUNBUFFERED=1"
EnvironmentFile=${INSTALL_DIR}/control-plane/.env

ExecStart=${UVICORN_PATH} main:app \\
    --host 0.0.0.0 \\
    --port ${HUB_API_PORT} \\
    --workers 2 \\
    --log-level info \\
    --access-log

Restart=always
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5

# Security Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${DATA_DIR} ${LOG_DIR} /etc/wireguard
PrivateTmp=true

# Logging
StandardOutput=append:${LOG_DIR}/control-plane.log
StandardError=append:${LOG_DIR}/control-plane.error.log

[Install]
WantedBy=multi-user.target
EOF

    # Log rotation
    cat > /etc/logrotate.d/zero-trust << EOF
${LOG_DIR}/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

    systemctl daemon-reload
    systemctl enable zero-trust-control-plane >/dev/null 2>&1
    systemctl restart zero-trust-control-plane

    log "Đợi Control Plane khởi động..."
    for i in {1..15}; do
        if curl -s "http://localhost:${HUB_API_PORT}/health" | grep -q "healthy"; then
            success "Control Plane đang chạy"
            return 0
        fi
        sleep 1
    done

    warn "Control Plane chưa phản hồi. Kiểm tra: journalctl -u zero-trust-control-plane -f"
}

# ==============================================================================
# PHASE 6: INSTALL CLI TOOL
# ==============================================================================
install_cli() {
    print_phase "6" "CÀI ĐẶT CLI TOOL"

    if [ -f "$INSTALL_DIR/scripts/ztctl" ]; then
        cp "$INSTALL_DIR/scripts/ztctl" /usr/local/bin/ztctl
        chmod +x /usr/local/bin/ztctl
        success "ztctl CLI đã cài đặt"
    fi

    mkdir -p /etc/zerotrust
    ADMIN_SECRET=$(grep ADMIN_SECRET "$INSTALL_DIR/control-plane/.env" | cut -d= -f2)
    cat > /etc/zerotrust/ztctl.conf << EOF
# ZTCTL Configuration
HUB_URL="http://localhost:${HUB_API_PORT}"
ADMIN_TOKEN="${ADMIN_SECRET}"
EOF
    chmod 600 /etc/zerotrust/ztctl.conf
    success "ztctl config tại /etc/zerotrust/ztctl.conf"
}

# ==============================================================================
# PHASE 7: CONFIGURE FIREWALL
# ==============================================================================
configure_firewall() {
    print_phase "7" "CẤU HÌNH FIREWALL"

    if command -v ufw &> /dev/null; then
        log "Cấu hình UFW..."
        ufw allow 22/tcp comment "SSH" >/dev/null 2>&1 || true
        ufw allow ${WG_PORT}/udp comment "WireGuard VPN" >/dev/null 2>&1 || true
        ufw allow ${HUB_API_PORT}/tcp comment "Zero Trust API" >/dev/null 2>&1 || true
        
        if ! ufw status | grep -q "active"; then
            echo "y" | ufw enable >/dev/null 2>&1 || true
        fi
        success "UFW đã cấu hình"
    else
        log "UFW không có sẵn, bỏ qua cấu hình firewall"
    fi
}

# ==============================================================================
# PHASE 8: SUMMARY
# ==============================================================================
show_summary() {
    print_phase "8" "HOÀN TẤT"

    WG_PUBLIC_KEY=$(cat /etc/wireguard/public.key 2>/dev/null)
    ADMIN_SECRET=$(grep ADMIN_SECRET "$INSTALL_DIR/control-plane/.env" | cut -d= -f2)

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                              ║${NC}"
    echo -e "${GREEN}║             ✅ ZERO TRUST HUB ĐÃ CÀI ĐẶT THÀNH CÔNG!                        ║${NC}"
    echo -e "${GREEN}║                                                                              ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}                                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}📍 THÔNG TIN HUB:${NC}"
    echo -e "${GREEN}║${NC}  ├─ API Endpoint:    ${CYAN}http://${PUBLIC_IP}:${HUB_API_PORT}${NC}"
    echo -e "${GREEN}║${NC}  ├─ WireGuard:       ${CYAN}${PUBLIC_IP}:${WG_PORT}${NC}"
    echo -e "${GREEN}║${NC}  ├─ Hub Public Key:  ${CYAN}${WG_PUBLIC_KEY}${NC}"
    echo -e "${GREEN}║${NC}  ├─ Overlay Network: ${CYAN}${WG_OVERLAY_NETWORK}${NC}"
    echo -e "${GREEN}║${NC}  └─ Hub Overlay IP:  ${CYAN}${WG_HUB_IP}${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🔐 ADMIN CREDENTIALS:${NC}"
    echo -e "${GREEN}║${NC}  └─ Admin Token:     ${YELLOW}${ADMIN_SECRET}${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}📂 ĐƯỜNG DẪN:${NC}"
    echo -e "${GREEN}║${NC}  ├─ Install:         ${INSTALL_DIR}"
    echo -e "${GREEN}║${NC}  ├─ Config:          ${CONFIG_DIR}"
    echo -e "${GREEN}║${NC}  ├─ Data:            ${DATA_DIR}"
    echo -e "${GREEN}║${NC}  └─ Logs:            ${LOG_DIR}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}📋 QUẢN LÝ SERVICES:${NC}"
    echo -e "${GREEN}║${NC}  ├─ systemctl status zero-trust-control-plane"
    echo -e "${GREEN}║${NC}  ├─ systemctl restart zero-trust-control-plane"
    echo -e "${GREEN}║${NC}  ├─ systemctl status wg-quick@wg0"
    echo -e "${GREEN}║${NC}  └─ journalctl -u zero-trust-control-plane -f"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🛠 CLI COMMANDS:${NC}"
    echo -e "${GREEN}║${NC}  ├─ ztctl status              # Xem trạng thái cluster"
    echo -e "${GREEN}║${NC}  ├─ ztctl node list           # Danh sách nodes"
    echo -e "${GREEN}║${NC}  ├─ ztctl policy list         # Danh sách policies"
    echo -e "${GREEN}║${NC}  └─ ztctl sync                # Đồng bộ policies"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🚀 BƯỚC TIẾP THEO - Cài đặt Agent trên các node:${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}curl -sL https://raw.githubusercontent.com/.../scripts/node/install.sh | \\${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}  sudo HUB_URL=http://${PUBLIC_IP}:${HUB_API_PORT} ROLE=app bash${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Save installation info
    cat > "$CONFIG_DIR/install-info.txt" << EOF
# Zero Trust Hub Installation Info
# Generated: $(date -Iseconds)

PUBLIC_IP=${PUBLIC_IP}
HUB_API_PORT=${HUB_API_PORT}
WG_PORT=${WG_PORT}
WG_PUBLIC_KEY=${WG_PUBLIC_KEY}
OVERLAY_NETWORK=${WG_OVERLAY_NETWORK}
HUB_OVERLAY_IP=${WG_HUB_IP}
INSTALL_DIR=${INSTALL_DIR}
ADMIN_SECRET=${ADMIN_SECRET}
EOF
    chmod 600 "$CONFIG_DIR/install-info.txt"
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    print_banner
    
    preflight_checks
    install_dependencies
    setup_directories
    setup_wireguard
    install_control_plane
    create_systemd_service
    install_cli
    configure_firewall
    show_summary
}

main "$@"
