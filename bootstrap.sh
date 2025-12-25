#!/bin/bash
# =============================================================================
# ZERO TRUST NETWORKING - BOOTSTRAP SCRIPT
# =============================================================================
# Chạy trên VPS mới để join WireGuard mesh chỉ với 1 lệnh:
#
#   curl -sSL https://raw.githubusercontent.com/YOUR_REPO/bootstrap.sh | bash -s -- 10.10.0.10 db-primary
#
# Hoặc sau khi clone repo:
#   ./bootstrap.sh 10.10.0.10 db-primary
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# HUB CONFIGURATION - CẬP NHẬT SAU KHI SETUP HUB
# =============================================================================
HUB_ENDPOINT="5.104.82.252"
HUB_PORT="51820"
HUB_PUBLIC_KEY="9c7Sd43PyenG33LjKho0TKykNCJbqgXwhJHRF0jloEs="
REPO_URL="https://github.com/YOUR_USERNAME/zero-trust-networking.git"
# =============================================================================

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
║                    🔐 WIREGUARD MESH BOOTSTRAP                               ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

show_usage() {
    echo "Usage: $0 <wireguard_ip> <node_name>"
    echo ""
    echo "Examples:"
    echo "  $0 10.10.0.10 db-primary"
    echo "  $0 10.10.0.11 db-replica"
    echo "  $0 10.10.0.20 odoo-app"
    echo ""
    echo "IP Ranges (suggested):"
    echo "  10.10.0.1       - Hub Server (đã cấu hình)"
    echo "  10.10.0.10-19   - Database nodes"
    echo "  10.10.0.20-29   - Application nodes"  
    echo "  10.10.0.30-39   - Monitoring nodes"
    echo ""
    echo "Hub Configuration:"
    echo "  Endpoint: $HUB_ENDPOINT:$HUB_PORT"
    echo "  Public Key: $HUB_PUBLIC_KEY"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Vui lòng chạy với quyền root: sudo $0 $*"
    exit 1
fi

print_banner

# Interactive mode if no arguments
if [ $# -lt 2 ]; then
    echo -e "${YELLOW}Chế độ tương tác - Nhập thông tin node:${NC}"
    echo ""
    
    # Show available IPs
    echo "IP Ranges gợi ý:"
    echo "  10.10.0.10-19   - Database nodes"
    echo "  10.10.0.20-29   - Application nodes"
    echo "  10.10.0.30-39   - Monitoring nodes"
    echo ""
    
    read -p "WireGuard IP cho node này (vd: 10.10.0.10): " WG_IP
    read -p "Tên node (vd: db-primary): " NODE_NAME
    
    if [ -z "$WG_IP" ] || [ -z "$NODE_NAME" ]; then
        print_error "Thiếu thông tin!"
        show_usage
        exit 1
    fi
else
    WG_IP="$1"
    NODE_NAME="$2"
fi

# Validate IP format
if ! [[ $WG_IP =~ ^10\.10\.0\.[0-9]+$ ]]; then
    print_error "IP không hợp lệ. Phải trong dải 10.10.0.x"
    exit 1
fi

echo ""
print_info "Cấu hình node:"
echo "  - Tên: $NODE_NAME"
echo "  - WireGuard IP: $WG_IP"
echo "  - Hub: $HUB_ENDPOINT:$HUB_PORT"
echo ""

# =============================================================================
# STEP 1: Install prerequisites
# =============================================================================
print_info "Bước 1/4: Cài đặt prerequisites..."

apt-get update -qq

# Install Ansible
if ! command -v ansible &> /dev/null; then
    apt-get install -y -qq software-properties-common
    add-apt-repository -y ppa:ansible/ansible > /dev/null 2>&1
    apt-get update -qq
    apt-get install -y -qq ansible
    print_success "Ansible đã cài đặt"
else
    print_success "Ansible đã có sẵn"
fi

# Install Git
if ! command -v git &> /dev/null; then
    apt-get install -y -qq git
    print_success "Git đã cài đặt"
else
    print_success "Git đã có sẵn"
fi

# =============================================================================
# STEP 2: Clone or update repo
# =============================================================================
print_info "Bước 2/4: Chuẩn bị project..."

PROJECT_DIR="/home/zero-trust-networking"

if [ -d "$PROJECT_DIR/.git" ]; then
    print_info "Project đã tồn tại, đang cập nhật..."
    cd "$PROJECT_DIR"
    git pull --quiet || true
else
    # Check if we're already in the project directory
    if [ -f "./playbooks/add-wireguard-peer.yml" ]; then
        PROJECT_DIR="$(pwd)"
        print_success "Đang sử dụng project hiện tại: $PROJECT_DIR"
    elif [ "$REPO_URL" != "https://github.com/YOUR_USERNAME/zero-trust-networking.git" ]; then
        print_info "Cloning repository..."
        git clone --quiet "$REPO_URL" "$PROJECT_DIR"
        cd "$PROJECT_DIR"
    else
        print_warning "REPO_URL chưa được cấu hình!"
        print_info "Vui lòng clone repo thủ công hoặc cập nhật REPO_URL trong script"
        
        # Fallback: create minimal structure
        print_info "Tạo cấu trúc tối thiểu..."
        mkdir -p "$PROJECT_DIR"
        cd "$PROJECT_DIR"
    fi
fi

cd "$PROJECT_DIR"

# =============================================================================
# STEP 3: Run Ansible playbook
# =============================================================================
print_info "Bước 3/4: Chạy Ansible playbook..."

if [ -f "./playbooks/setup-worker-node.yml" ]; then
    ansible-playbook playbooks/setup-worker-node.yml \
        -e "wg_address=$WG_IP" \
        -e "node_name=$NODE_NAME"
elif [ -f "./playbooks/add-wireguard-peer.yml" ]; then
    ansible-playbook playbooks/add-wireguard-peer.yml \
        -e "wg_address=$WG_IP" \
        -e "wg_peer_name=$NODE_NAME" \
        -e "wg_hub_endpoint=$HUB_ENDPOINT" \
        -e "wg_hub_public_key=$HUB_PUBLIC_KEY"
else
    # Fallback: Direct WireGuard setup if playbook not available
    print_warning "Playbook không tìm thấy, setup trực tiếp..."
    
    apt-get install -y -qq wireguard wireguard-tools
    
    mkdir -p /etc/wireguard
    chmod 700 /etc/wireguard
    
    # Generate keys if not exist
    if [ ! -f /etc/wireguard/private.key ]; then
        wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
        chmod 600 /etc/wireguard/private.key
    fi
    
    PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    PUBLIC_KEY=$(cat /etc/wireguard/public.key)
    
    # Create config
    cat > /etc/wireguard/wg0.conf << EOF
# $NODE_NAME - Generated by bootstrap.sh
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $WG_IP/24

[Peer]
# Hub Server
PublicKey = $HUB_PUBLIC_KEY
Endpoint = $HUB_ENDPOINT:$HUB_PORT
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
    sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null
    
    # Start WireGuard
    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0
    
    print_success "WireGuard đã cấu hình"
fi

# =============================================================================
# STEP 4: Display results
# =============================================================================
sleep 2
PUBLIC_KEY=$(cat /etc/wireguard/public.key 2>/dev/null || echo "ERROR")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ BOOTSTRAP HOÀN TẤT!                                          ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Node: $NODE_NAME${NC}"
echo -e "${GREEN}║  WireGuard IP: $WG_IP${NC}"
echo -e "${GREEN}║                                                                              ║${NC}"
echo -e "${GREEN}║  🔑 PUBLIC KEY:                                                              ║${NC}"
echo -e "${YELLOW}║  $PUBLIC_KEY${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  📋 BƯỚC TIẾP THEO - Chạy trên Hub ($HUB_ENDPOINT):                          ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${NC}║${NC}"
echo -e "${YELLOW}║  cd /home/zero-trust-netwoking${NC}"
echo -e "${YELLOW}║  ./scripts/add-peer-to-hub.sh \"$NODE_NAME\" \\${NC}"
echo -e "${YELLOW}║      \"$PUBLIC_KEY\" \\${NC}"
echo -e "${YELLOW}║      \"$WG_IP\"${NC}"
echo -e "${NC}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"

# Test connection (will fail until peer added to hub)
echo ""
print_info "Testing connection to Hub (10.10.0.1)..."
if ping -c 2 -W 3 10.10.0.1 &>/dev/null; then
    print_success "Hub đã reachable! Kết nối thành công."
else
    print_warning "Hub chưa reachable. Cần thêm peer vào Hub trước (xem hướng dẫn ở trên)."
fi

echo ""
print_info "WireGuard Status:"
wg show wg0 2>/dev/null || echo "WireGuard chưa active"
