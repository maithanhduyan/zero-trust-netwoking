#!/bin/bash
# ==============================================================================
# ZERO TRUST NETWORK - NODE UNINSTALLER
# Removes Agent and WireGuard configuration from spoke node
# ==============================================================================
#
# Usage:
#   sudo ./uninstall.sh              # Interactive mode
#   sudo ./uninstall.sh --force      # Skip confirmations
#   sudo ./uninstall.sh --dry-run    # Preview only
#   sudo ./uninstall.sh --keep-keys  # Keep WireGuard keys for re-registration
#
# ==============================================================================

set -e

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || {
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
    log() { echo -e "${BLUE}[INFO]${NC} $1"; }
    success() { echo -e "${GREEN}[OK]${NC} $1"; }
    warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
    error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
}

# Parse arguments
FORCE=false
DRY_RUN=false
KEEP_KEYS=false
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
        --keep-keys) KEEP_KEYS=true ;;
    esac
done

# Banner
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║              ⚠️  ZERO TRUST NODE UNINSTALLER                         ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  This will remove:                                                   ║${NC}"
echo -e "${RED}║  - Zero Trust Agent service                                          ║${NC}"
echo -e "${RED}║  - WireGuard configuration                                           ║${NC}"
echo -e "${RED}║  - Firewall rules (ZT_ACL chain)                                     ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show current info
if [ -f /etc/zerotrust/agent.conf ]; then
    HOSTNAME=$(grep "^hostname" /etc/zerotrust/agent.conf | cut -d'=' -f2 | tr -d ' ')
    ROLE=$(grep "^role" /etc/zerotrust/agent.conf | cut -d'=' -f2 | tr -d ' ')
    echo -e "  Node: ${YELLOW}${HOSTNAME}${NC} (${ROLE})"
fi
if [ -f /etc/wireguard/overlay_ip ]; then
    OVERLAY_IP=$(cat /etc/wireguard/overlay_ip)
    echo -e "  Overlay IP: ${YELLOW}${OVERLAY_IP}${NC}"
fi
echo ""

# Confirmation
if [ "$FORCE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
    read -p "Nhập 'UNINSTALL' để xác nhận: " confirm
    if [ "$confirm" != "UNINSTALL" ]; then
        echo "Hủy bỏ."
        exit 0
    fi
fi

run_cmd() {
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $1"
    else
        eval "$1"
    fi
}

# ==============================================================================
# PHASE 1: STOP SERVICES
# ==============================================================================
echo ""
log "Phase 1: Dừng services..."

# Stop Agent
if systemctl is-active --quiet zero-trust-agent 2>/dev/null; then
    run_cmd "systemctl stop zero-trust-agent"
    run_cmd "systemctl disable zero-trust-agent 2>/dev/null || true"
    success "Đã dừng Agent"
else
    log "Agent không chạy"
fi

# Stop WireGuard
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
    run_cmd "systemctl stop wg-quick@wg0"
    run_cmd "systemctl disable wg-quick@wg0 2>/dev/null || true"
    success "Đã dừng WireGuard"
else
    log "WireGuard không chạy"
fi

# ==============================================================================
# PHASE 2: REMOVE FIREWALL RULES
# ==============================================================================
echo ""
log "Phase 2: Xóa firewall rules..."

# Remove ZT_ACL chain references from INPUT
run_cmd "iptables -D INPUT -i wg0 -j ZT_ACL 2>/dev/null || true"
run_cmd "iptables -D FORWARD -i wg0 -j ZT_ACL 2>/dev/null || true"

# Flush and delete ZT_ACL chain
run_cmd "iptables -F ZT_ACL 2>/dev/null || true"
run_cmd "iptables -X ZT_ACL 2>/dev/null || true"

success "Đã xóa ZT_ACL chain"

# ==============================================================================
# PHASE 3: REMOVE CONFIGURATION
# ==============================================================================
echo ""
log "Phase 3: Xóa cấu hình..."

# Remove systemd service
if [ -f /etc/systemd/system/zero-trust-agent.service ]; then
    run_cmd "rm -f /etc/systemd/system/zero-trust-agent.service"
    run_cmd "systemctl daemon-reload"
    success "Đã xóa systemd service"
fi

# Remove agent config
if [ -d /etc/zerotrust ]; then
    run_cmd "rm -rf /etc/zerotrust"
    success "Đã xóa agent config"
fi

# Remove WireGuard config
if [ -d /etc/wireguard ]; then
    if [ "$KEEP_KEYS" = "true" ]; then
        # Keep keys, only remove config
        run_cmd "rm -f /etc/wireguard/wg0.conf"
        run_cmd "rm -f /etc/wireguard/overlay_ip"
        success "Đã xóa WireGuard config (giữ lại keys)"
    else
        # Backup first
        if [ "$DRY_RUN" != "true" ]; then
            BACKUP_DIR="/root/wireguard-backup-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$BACKUP_DIR"
            cp -r /etc/wireguard/* "$BACKUP_DIR/" 2>/dev/null || true
            log "Backup WireGuard tại: $BACKUP_DIR"
        fi
        run_cmd "rm -rf /etc/wireguard/*"
        success "Đã xóa WireGuard config và keys"
    fi
fi

# ==============================================================================
# PHASE 4: REMOVE APPLICATION
# ==============================================================================
echo ""
log "Phase 4: Xóa ứng dụng..."

# Remove agent directory
if [ -d /opt/zero-trust-agent ]; then
    run_cmd "rm -rf /opt/zero-trust-agent"
    success "Đã xóa /opt/zero-trust-agent"
fi

# Remove logs
if [ -d /var/log/zerotrust ]; then
    run_cmd "rm -rf /var/log/zerotrust"
    success "Đã xóa logs"
fi

# ==============================================================================
# PHASE 5: SUMMARY
# ==============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${GREEN}║              DRY-RUN HOÀN TẤT - Không có gì bị xóa                  ║${NC}"
else
    echo -e "${GREEN}║              ✅ NODE ĐÃ ĐƯỢC GỠ CÀI ĐẶT                              ║${NC}"
fi
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                                      ║${NC}"
echo -e "${GREEN}║${NC}  Đã gỡ bỏ:"
echo -e "${GREEN}║${NC}    - Zero Trust Agent service"
echo -e "${GREEN}║${NC}    - WireGuard configuration"
echo -e "${GREEN}║${NC}    - Firewall rules (ZT_ACL)"
if [ "$KEEP_KEYS" = "true" ]; then
    echo -e "${GREEN}║${NC}    - (Giữ lại WireGuard keys)"
fi
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Để cài đặt lại:"
echo -e "${GREEN}║${NC}    curl -sL .../scripts/node/install.sh | HUB_URL=... bash"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
