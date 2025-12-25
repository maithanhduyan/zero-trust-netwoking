#!/bin/bash
# =============================================================================
# QUICK SETUP PEER - Script chạy trên VPS mới để join WireGuard mesh
# =============================================================================
# Script này sẽ:
# 1. Cài đặt WireGuard
# 2. Generate keys
# 3. Cấu hình kết nối đến Hub
# 4. In ra public key để thêm vào Hub
#
# Usage: curl -sSL <url>/quick-peer-setup.sh | bash -s -- <wg_ip> <peer_name>
# Or: ./scripts/quick-peer-setup.sh 10.10.0.10 db-primary
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# CẤU HÌNH HUB SERVER - THAY ĐỔI NẾU CẦN
# =============================================================================
HUB_ENDPOINT="5.104.82.252"
HUB_PORT="51820"
HUB_PUBLIC_KEY="9c7Sd43PyenG33LjKho0TKykNCJbqgXwhJHRF0jloEs="
WG_NETWORK="10.10.0.0/24"
# =============================================================================

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║         🔐 WIREGUARD PEER QUICK SETUP                                ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo $0 $*"
    exit 1
fi

# Check arguments
if [ $# -lt 2 ]; then
    print_header
    echo "Usage: $0 <wireguard_ip> <node_name>"
    echo ""
    echo "Examples:"
    echo "  $0 10.10.0.10 db-primary"
    echo "  $0 10.10.0.11 db-replica"
    echo "  $0 10.10.0.20 odoo-app"
    echo ""
    echo "Hub Configuration:"
    echo "  Endpoint: $HUB_ENDPOINT:$HUB_PORT"
    echo "  Public Key: $HUB_PUBLIC_KEY"
    echo ""
    echo "Suggested IP ranges:"
    echo "  10.10.0.10-19  - Database nodes"
    echo "  10.10.0.20-29  - Application nodes"
    echo "  10.10.0.30-39  - Monitoring nodes"
    exit 1
fi

WG_IP="$1"
NODE_NAME="$2"

print_header
print_info "Setting up WireGuard peer: $NODE_NAME"
print_info "WireGuard IP: $WG_IP"
print_info "Hub: $HUB_ENDPOINT:$HUB_PORT"
echo ""

# =============================================================================
# STEP 1: Install WireGuard
# =============================================================================
print_info "Installing WireGuard..."

apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools

print_success "WireGuard installed"

# =============================================================================
# STEP 2: Enable IP forwarding
# =============================================================================
print_info "Enabling IP forwarding..."

cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-wireguard.conf > /dev/null

print_success "IP forwarding enabled"

# =============================================================================
# STEP 3: Generate keys
# =============================================================================
print_info "Generating WireGuard keys..."

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# Check if keys already exist
if [ -f /etc/wireguard/private.key ]; then
    print_warning "Keys already exist, using existing keys"
    PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    PUBLIC_KEY=$(cat /etc/wireguard/public.key)
else
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
    
    echo "$PRIVATE_KEY" > /etc/wireguard/private.key
    chmod 600 /etc/wireguard/private.key
    
    echo "$PUBLIC_KEY" > /etc/wireguard/public.key
    chmod 644 /etc/wireguard/public.key
    
    print_success "Keys generated"
fi

# =============================================================================
# STEP 4: Create WireGuard config
# =============================================================================
print_info "Creating WireGuard configuration..."

cat > /etc/wireguard/wg0.conf << EOF
# =============================================================================
# WIREGUARD CONFIGURATION - $NODE_NAME
# =============================================================================
# Generated: $(date)
# Hub: $HUB_ENDPOINT:$HUB_PORT
# =============================================================================

[Interface]
PrivateKey = $PRIVATE_KEY
Address = $WG_IP/24

# =============================================================================
# HUB SERVER
# =============================================================================
[Peer]
# Hub Server
PublicKey = $HUB_PUBLIC_KEY
Endpoint = $HUB_ENDPOINT:$HUB_PORT
AllowedIPs = $WG_NETWORK
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

print_success "Configuration created at /etc/wireguard/wg0.conf"

# =============================================================================
# STEP 5: Start WireGuard
# =============================================================================
print_info "Starting WireGuard..."

# Stop if already running
systemctl stop wg-quick@wg0 2>/dev/null || true

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

sleep 2

print_success "WireGuard started"

# =============================================================================
# STEP 6: Configure firewall (optional)
# =============================================================================
if command -v ufw &> /dev/null; then
    print_info "Configuring UFW firewall..."
    ufw allow 51820/udp comment "WireGuard" > /dev/null 2>&1 || true
    ufw allow in on wg0 comment "WireGuard traffic" > /dev/null 2>&1 || true
    print_success "Firewall configured"
fi

# =============================================================================
# FINAL: Display results and next steps
# =============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ WIREGUARD PEER SETUP COMPLETE!                               ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                                              ║${NC}"
echo -e "${GREEN}║  📋 NODE INFORMATION:                                                        ║${NC}"
echo -e "${GREEN}║     Name: $NODE_NAME${NC}"
echo -e "${GREEN}║     WireGuard IP: $WG_IP${NC}"
echo -e "${GREEN}║                                                                              ║${NC}"
echo -e "${GREEN}║  🔑 PUBLIC KEY (copy this):                                                  ║${NC}"
echo -e "${YELLOW}║     $PUBLIC_KEY${NC}"
echo -e "${GREEN}║                                                                              ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  📝 NEXT STEP - Run on Hub Server ($HUB_ENDPOINT):                           ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                                              ║${NC}"
echo -e "${NC}║  Option 1 - Using script:${NC}"
echo -e "${YELLOW}║    ./scripts/add-peer-to-hub.sh \"$NODE_NAME\" \"$PUBLIC_KEY\" \"$WG_IP\"${NC}"
echo -e "${GREEN}║                                                                              ║${NC}"
echo -e "${NC}║  Option 2 - Manual:${NC}"
echo -e "${YELLOW}║    cat >> /etc/wireguard/wg0.conf << 'EOF'${NC}"
echo -e "${YELLOW}║    ${NC}"
echo -e "${YELLOW}║    [Peer]${NC}"
echo -e "${YELLOW}║    # $NODE_NAME${NC}"
echo -e "${YELLOW}║    PublicKey = $PUBLIC_KEY${NC}"
echo -e "${YELLOW}║    AllowedIPs = $WG_IP/32${NC}"
echo -e "${YELLOW}║    EOF${NC}"
echo -e "${YELLOW}║    ${NC}"
echo -e "${YELLOW}║    wg syncconf wg0 <(wg-quick strip wg0)${NC}"
echo -e "${GREEN}║                                                                              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show current status
print_info "WireGuard Status:"
echo "----------------------------------------"
wg show wg0
echo "----------------------------------------"

# Test ping to hub (will fail until we add peer to hub)
echo ""
print_info "Testing connection to Hub (10.10.0.1)..."
if ping -c 2 -W 3 10.10.0.1 &>/dev/null; then
    print_success "Hub is reachable! Connection working."
else
    print_warning "Hub not reachable yet. Add this peer to Hub first using the command above."
fi
