#!/bin/bash
# =============================================================================
# SCRIPT TỰ ĐỘNG THÊM PEER VÀO HUB SERVER
# =============================================================================
# Chạy script này trên HUB SERVER để thêm peer mới
# 
# Usage: ./scripts/add-peer-to-hub.sh <peer_name> <peer_public_key> <peer_wg_ip>
# Example: ./scripts/add-peer-to-hub.sh db-primary "ABC123pubkey=" 10.10.0.10
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║         🔗 ADD WIREGUARD PEER TO HUB                                 ║"
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

# Check arguments
if [ $# -lt 3 ]; then
    print_header
    echo "Usage: $0 <peer_name> <peer_public_key> <peer_wg_ip>"
    echo ""
    echo "Example:"
    echo "  $0 db-primary 'ABC123publickey=' 10.10.0.10"
    echo "  $0 db-replica 'XYZ789publickey=' 10.10.0.11"
    echo "  $0 odoo-app 'DEF456publickey=' 10.10.0.20"
    echo ""
    echo "Available IP ranges (suggested):"
    echo "  10.10.0.1      - Hub Server (already configured)"
    echo "  10.10.0.10-19  - Database nodes"
    echo "  10.10.0.20-29  - Application nodes"
    echo "  10.10.0.30-39  - Monitoring nodes"
    echo "  10.10.0.100+   - Additional nodes"
    exit 1
fi

PEER_NAME="$1"
PEER_PUBLIC_KEY="$2"
PEER_WG_IP="$3"
WG_CONF="/etc/wireguard/wg0.conf"

print_header

# Check if running on hub
if [ ! -f "$WG_CONF" ]; then
    print_error "WireGuard config not found at $WG_CONF"
    print_error "This script must be run on the Hub Server!"
    exit 1
fi

# Check if peer already exists
if grep -q "$PEER_PUBLIC_KEY" "$WG_CONF"; then
    print_warning "Peer with this public key already exists!"
    print_info "Checking existing configuration..."
    grep -A 2 "$PEER_PUBLIC_KEY" "$WG_CONF"
    exit 1
fi

if grep -q "AllowedIPs = ${PEER_WG_IP}/32" "$WG_CONF"; then
    print_warning "IP ${PEER_WG_IP} is already assigned to another peer!"
    exit 1
fi

print_info "Adding peer: $PEER_NAME"
print_info "Public Key: $PEER_PUBLIC_KEY"
print_info "WireGuard IP: $PEER_WG_IP"
echo ""

# Backup current config
BACKUP_FILE="${WG_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$WG_CONF" "$BACKUP_FILE"
print_success "Backed up config to: $BACKUP_FILE"

# Add peer to config
cat >> "$WG_CONF" << EOF

[Peer]
# $PEER_NAME
PublicKey = $PEER_PUBLIC_KEY
AllowedIPs = ${PEER_WG_IP}/32
EOF

print_success "Added peer configuration to $WG_CONF"

# Apply configuration without restart
print_info "Applying configuration..."
if wg syncconf wg0 <(wg-quick strip wg0); then
    print_success "Configuration applied successfully!"
else
    print_error "Failed to apply configuration, restoring backup..."
    cp "$BACKUP_FILE" "$WG_CONF"
    exit 1
fi

# Show current peers
echo ""
print_info "Current WireGuard peers:"
echo "----------------------------------------"
wg show wg0 peers
echo ""

# Test connectivity (might fail if peer hasn't connected yet)
print_info "Testing connectivity to $PEER_WG_IP..."
if ping -c 2 -W 3 "$PEER_WG_IP" &>/dev/null; then
    print_success "Peer $PEER_NAME ($PEER_WG_IP) is reachable!"
else
    print_warning "Peer not reachable yet. This is normal if the peer hasn't connected."
    print_info "The peer should be able to connect now. Verify with:"
    echo "  ping $PEER_WG_IP"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✅ PEER ADDED SUCCESSFULLY!                                  ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  Peer Name: $PEER_NAME${NC}"
echo -e "${GREEN}║  WireGuard IP: $PEER_WG_IP${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
