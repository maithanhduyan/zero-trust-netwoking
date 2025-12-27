#!/bin/bash
# ==============================================================================
#  ZERO TRUST CONTROL PLANE - AUTOMATED INSTALLER
#  Repository: https://github.com/maithanhduyan/zero-trust-netwoking
# ==============================================================================
#
#  Usage:
#    curl -sL https://raw.githubusercontent.com/maithanhduyan/zero-trust-netwoking/main/scripts/install.sh | sudo bash
#
#    Or download and run:
#    chmod +x install.sh && sudo ./install.sh
#
# ==============================================================================

set -e

# --- CẤU HÌNH ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/zero-trust-control-plane}"
REPO_URL="https://github.com/maithanhduyan/zero-trust-netwoking.git"
BRANCH="${BRANCH:-main}"
WG_ADDRESS="10.10.0.1"
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
║              ZERO TRUST NETWORKING - CONTROL PLANE INSTALLER                       ║
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
# PHASE 0: CHECK ENVIRONMENT
# ==============================================================================
check_environment() {
    print_phase "0" "KIỂM TRA MÔI TRƯỜNG"

    # Check root
    if [ "$(id -u)" -ne 0 ]; then
        error "Script này cần quyền root. Vui lòng chạy với 'sudo'."
    fi
    success "Đang chạy với quyền root"

    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log "Hệ điều hành: $PRETTY_NAME"
    fi

    # Check architecture
    ARCH=$(uname -m)
    log "Kiến trúc: $ARCH"

    # Install base packages
    log "Cài đặt các gói cơ bản..."
    apt-get update -qq
    apt-get install -y -qq curl git openssl ca-certificates gnupg lsb-release >/dev/null 2>&1
    success "Các gói cơ bản đã sẵn sàng"
}

# ==============================================================================
# PHASE 1: INSTALL DEPENDENCIES
# ==============================================================================
install_docker() {
    log "Kiểm tra Docker..."

    if command -v docker &> /dev/null; then
        success "Docker đã có sẵn: $(docker --version)"
        return
    fi

    log "Đang cài đặt Docker..."
    curl -fsSL https://get.docker.com | sh

    # Start Docker
    systemctl enable docker
    systemctl start docker

    success "Docker đã cài đặt: $(docker --version)"
}

install_wireguard() {
    log "Kiểm tra WireGuard..."

    if command -v wg &> /dev/null; then
        success "WireGuard đã có sẵn: $(wg --version 2>&1 | head -1)"
        return
    fi

    log "Đang cài đặt WireGuard..."
    apt-get install -y -qq wireguard wireguard-tools >/dev/null 2>&1

    success "WireGuard đã cài đặt"
}

install_uv() {
    log "Kiểm tra uv (Python package manager)..."

    if command -v uv &> /dev/null; then
        success "uv đã có sẵn: $(uv --version)"
        return
    fi

    log "Đang cài đặt uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Add to PATH for current session
    export PATH="$HOME/.local/bin:$PATH"

    success "uv đã cài đặt"
}

install_dependencies() {
    print_phase "1" "CÀI ĐẶT DEPENDENCIES"

    install_docker
    install_wireguard
    install_uv

    # Enable IP forwarding
    log "Bật IP forwarding..."
    cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
    sysctl -p /etc/sysctl.d/99-wireguard.conf >/dev/null 2>&1
    success "IP forwarding đã bật"
}

# ==============================================================================
# PHASE 2: SETUP WIREGUARD HUB
# ==============================================================================
setup_wireguard_hub() {
    print_phase "2" "CẤU HÌNH WIREGUARD HUB"

    # Create WireGuard directory
    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard

    # Generate keys if not exists
    if [ ! -f /etc/wireguard/private.key ]; then
        log "Đang tạo keypair cho Hub..."
        wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
        chmod 600 /etc/wireguard/private.key
        success "Đã tạo keypair mới"
    else
        success "Keypair đã tồn tại"
    fi

    # Read keys
    WG_PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    WG_PUBLIC_KEY=$(cat /etc/wireguard/public.key)

    # Get public IPv4 (prefer -4 flag to get IPv4 instead of IPv6)
    PUBLIC_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || \
                curl -4 -s --max-time 5 ipv4.icanhazip.com 2>/dev/null || \
                echo "YOUR_PUBLIC_IP")

    # Get default interface
    DEFAULT_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

    # Create WireGuard config
    log "Tạo cấu hình WireGuard Hub..."
    cat > /etc/wireguard/wg0.conf << EOF
# ==============================================================================
# WIREGUARD HUB CONFIGURATION
# Generated by Zero Trust Installer - $(date -Iseconds)
# ==============================================================================

[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = ${WG_ADDRESS}/24
ListenPort = ${WG_PORT}

# NAT Masquerade - cho phép routing giữa các peers
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${DEFAULT_IFACE} -j MASQUERADE

# ==============================================================================
# PEERS - Các node sẽ được thêm tự động bởi Control Plane
# ==============================================================================
EOF
    chmod 600 /etc/wireguard/wg0.conf

    # Start WireGuard
    log "Khởi động WireGuard..."
    systemctl enable wg-quick@wg0 >/dev/null 2>&1
    systemctl restart wg-quick@wg0 || systemctl start wg-quick@wg0

    # Verify
    if wg show wg0 >/dev/null 2>&1; then
        success "WireGuard Hub đang chạy trên ${WG_ADDRESS}:${WG_PORT}"
    else
        warn "Không thể khởi động WireGuard. Kiểm tra logs: journalctl -u wg-quick@wg0"
    fi

    # Open firewall port
    if command -v ufw &> /dev/null; then
        ufw allow ${WG_PORT}/udp comment "WireGuard VPN" >/dev/null 2>&1 || true
    fi

    # Save public info for later
    echo "$WG_PUBLIC_KEY" > /etc/wireguard/hub_public_key
    echo "$PUBLIC_IP" > /etc/wireguard/hub_endpoint
}

# ==============================================================================
# PHASE 3: SETUP CONTROL PLANE
# ==============================================================================
setup_control_plane() {
    print_phase "3" "CÀI ĐẶT CONTROL PLANE"

    # Use current directory if it's the repo, otherwise use INSTALL_DIR
    if [ -f "$SCRIPT_DIR/../control-plane/main.py" ]; then
        INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
        log "Sử dụng thư mục hiện tại: $INSTALL_DIR"
    elif [ -d "$INSTALL_DIR/.git" ]; then
        log "Cập nhật repository..."
        cd "$INSTALL_DIR"
        git fetch origin
        git reset --hard "origin/$BRANCH"
    elif [ ! -d "$INSTALL_DIR" ]; then
        log "Clone repository..."
        git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    fi

    cd "$INSTALL_DIR"
    success "Mã nguồn tại: $INSTALL_DIR"

    # Read WireGuard info
    WG_PUBLIC_KEY=$(cat /etc/wireguard/public.key 2>/dev/null || echo "REPLACE_WITH_HUB_PUBLIC_KEY")
    PUBLIC_IP=$(cat /etc/wireguard/hub_endpoint 2>/dev/null || \
                curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -4 -s --max-time 5 ipv4.icanhazip.com 2>/dev/null || \
                echo "127.0.0.1")

    # Create .env file for control-plane
    log "Tạo cấu hình Control Plane..."
    cat > "$INSTALL_DIR/control-plane/.env" << EOF
# ==============================================================================
# ZERO TRUST CONTROL PLANE CONFIGURATION
# Generated by install.sh - $(date -Iseconds)
# ==============================================================================

# Server
HOST=0.0.0.0
PORT=8000

# Database
DATABASE_URL=sqlite:///./zerotrust.db

# WireGuard Hub Configuration
HUB_PUBLIC_KEY=${WG_PUBLIC_KEY}
HUB_ENDPOINT=${PUBLIC_IP}:${WG_PORT}
OVERLAY_NETWORK=${WG_NETWORK}

# Security
SECRET_KEY=$(openssl rand -hex 32)
EOF

    # Update config.py with hub info
    log "Cập nhật cấu hình Hub..."
    if [ -f "$INSTALL_DIR/control-plane/config.py" ]; then
        sed -i "s|REPLACE_WITH_HUB_PUBLIC_KEY|${WG_PUBLIC_KEY}|g" "$INSTALL_DIR/control-plane/config.py" 2>/dev/null || true
        sed -i "s|hub.example.com:51820|${PUBLIC_IP}:${WG_PORT}|g" "$INSTALL_DIR/control-plane/config.py" 2>/dev/null || true
    fi

    success "Control Plane đã cấu hình"
}

# ==============================================================================
# PHASE 4: START SERVICES
# ==============================================================================
start_services() {
    print_phase "4" "KHỞI ĐỘNG SERVICES"

    cd "$INSTALL_DIR/control-plane"

    # Install Python dependencies
    log "Cài đặt Python dependencies..."

    # Check if uv is available
    if command -v uv &> /dev/null; then
        uv sync 2>/dev/null || uv pip install -r pyproject.toml 2>/dev/null || {
            # Fallback: install individually
            uv pip install fastapi uvicorn sqlalchemy pydantic pyyaml aiofiles python-multipart
        }
    else
        # Use pip if uv not available
        pip3 install fastapi uvicorn sqlalchemy pydantic pyyaml aiofiles python-multipart
    fi
    success "Dependencies đã cài đặt"

    # Create systemd service
    log "Tạo systemd service..."
    cat > /etc/systemd/system/zero-trust-control-plane.service << EOF
[Unit]
Description=Zero Trust Control Plane API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/control-plane
Environment="PATH=/root/.local/bin:/usr/local/bin:/usr/bin"
ExecStart=/root/.local/bin/uv run uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Reload and start
    systemctl daemon-reload
    systemctl enable zero-trust-control-plane
    systemctl restart zero-trust-control-plane

    # Wait for service to start
    log "Đợi Control Plane khởi động..."
    sleep 3

    # Check health
    for i in {1..10}; do
        if curl -s http://localhost:8000/health | grep -q "healthy"; then
            success "Control Plane API đang chạy"
            return
        fi
        sleep 1
    done

    warn "Control Plane chưa respond. Kiểm tra: journalctl -u zero-trust-control-plane -f"
}

# ==============================================================================
# PHASE 5: VERIFY & SHOW SUMMARY
# ==============================================================================
show_summary() {
    print_phase "5" "HOÀN TẤT"

    # Get info
    WG_PUBLIC_KEY=$(cat /etc/wireguard/public.key 2>/dev/null || echo "N/A")
    PUBLIC_IP=$(cat /etc/wireguard/hub_endpoint 2>/dev/null || \
                curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -4 -s --max-time 5 ipv4.icanhazip.com 2>/dev/null || \
                echo "N/A")
    WG_STATUS=$(wg show wg0 2>/dev/null | head -5 || echo "Not running")
    API_STATUS=$(curl -s http://localhost:8000/health 2>/dev/null | grep -o '"status":"[^"]*"' || echo "Not responding")

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              ✅ ZERO TRUST CONTROL PLANE ĐÃ CÀI ĐẶT!                 ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                                      ║${NC}"
    echo -e "${GREEN}║${NC}  📂 Thư mục cài đặt: ${YELLOW}${INSTALL_DIR}${NC}"
    echo -e "${GREEN}║${NC}  🌐 Control Plane:   ${YELLOW}http://${PUBLIC_IP}:8000${NC}"
    echo -e "${GREEN}║${NC}  🔒 WireGuard Hub:   ${YELLOW}${PUBLIC_IP}:${WG_PORT}${NC}"
    echo -e "${GREEN}║${NC}  🔑 Hub Public Key:  ${YELLOW}${WG_PUBLIC_KEY}${NC}"
    echo -e "${GREEN}║${NC}  🌍 Overlay Network: ${YELLOW}${WG_NETWORK}${NC}"
    echo -e "${GREEN}║                                                                      ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  API Status: ${API_STATUS}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}BƯỚC TIẾP THEO:${NC}"
    echo -e "${GREEN}║${NC}  1. Kiểm tra API: curl http://localhost:8000/health"
    echo -e "${GREEN}║${NC}  2. Xem logs: journalctl -u zero-trust-control-plane -f"
    echo -e "${GREEN}║${NC}  3. Triển khai agents lên các node khác"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${CYAN}QUẢN LÝ SERVICES:${NC}"
    echo -e "${GREEN}║${NC}  - Control Plane: systemctl {start|stop|restart} zero-trust-control-plane"
    echo -e "${GREEN}║${NC}  - WireGuard:     systemctl {start|stop|restart} wg-quick@wg0"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    print_banner

    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ZERO TRUST NETWORKING - Control Plane Installer v2.0${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo ""

    check_environment
    install_dependencies
    setup_wireguard_hub
    setup_control_plane
    start_services
    show_summary
}

# Run
main "$@"
