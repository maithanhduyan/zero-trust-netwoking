#!/bin/bash
# ==============================================================================
# ZERO TRUST NETWORK - NODE UNINSTALLER
# Removes Agent and WireGuard from node
# ==============================================================================
#
# Usage:
#   sudo ./uninstall.sh              # Interactive
#   sudo ./uninstall.sh --force      # Skip confirmations
#   sudo ./uninstall.sh --dry-run    # Preview only
#
# ==============================================================================

set -e

# Configuration
CONFIG_DIR="/etc/zero-trust"
LOG_DIR="/var/log/zero-trust"
DATA_DIR="/var/lib/zero-trust"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $1"; }

# Parse arguments
FORCE=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --force|-f) FORCE=true ;;
        --dry-run|-n) DRY_RUN=true ;;
    esac
done

run_cmd() {
    local desc="$1"
    local cmd="$2"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would: $desc"
    else
        log "$desc"
        eval "$cmd" 2>/dev/null || true
    fi
}

# Banner
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║              ⚠️  ZERO TRUST NODE UNINSTALLER                         ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  Sẽ xóa:                                                             ║${NC}"
echo -e "${RED}║  • WireGuard interface (wg0) và config                               ║${NC}"
echo -e "${RED}║  • Zero Trust Agent service                                          ║${NC}"
echo -e "${RED}║  • ZT_ACL firewall chain                                             ║${NC}"
echo -e "${RED}║  • Config và log files                                               ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Confirmation
if [ "$FORCE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
    echo -e "${YELLOW}⚠️  CẢNH BÁO: Node sẽ mất kết nối với Zero Trust Network!${NC}"
    echo ""
    read -p "Nhập 'UNINSTALL' để xác nhận: " confirm
    if [ "$confirm" != "UNINSTALL" ]; then
        echo "Hủy bỏ."
        exit 0
    fi
fi

# ==============================================================================
# PHASE 1: STOP SERVICES
# ==============================================================================
echo ""
log "━━━ PHASE 1: DỪNG SERVICES ━━━"

# Stop agent timer
if systemctl is-active --quiet zero-trust-agent.timer 2>/dev/null; then
    run_cmd "Dừng agent timer" "systemctl stop zero-trust-agent.timer"
fi
run_cmd "Disable agent timer" "systemctl disable zero-trust-agent.timer"

# Stop WireGuard
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
    run_cmd "Dừng WireGuard" "systemctl stop wg-quick@wg0"
    success "Đã dừng WireGuard"
fi
run_cmd "Disable WireGuard" "systemctl disable wg-quick@wg0"

# ==============================================================================
# PHASE 2: REMOVE ZERO TRUST FIREWALL
# ==============================================================================
echo ""
log "━━━ PHASE 2: XÓA FIREWALL RULES ━━━"

# Remove ZT_ACL chain
run_cmd "Xóa ZT_ACL từ INPUT" "iptables -D INPUT -i wg0 -j ZT_ACL"
run_cmd "Flush ZT_ACL" "iptables -F ZT_ACL"
run_cmd "Xóa ZT_ACL chain" "iptables -X ZT_ACL"
success "Đã xóa ZT_ACL firewall"

# ==============================================================================
# PHASE 3: REMOVE SYSTEMD FILES
# ==============================================================================
echo ""
log "━━━ PHASE 3: XÓA SYSTEMD FILES ━━━"

run_cmd "Xóa agent service" "rm -f /etc/systemd/system/zero-trust-agent.service"
run_cmd "Xóa agent timer" "rm -f /etc/systemd/system/zero-trust-agent.timer"
run_cmd "Reload systemd" "systemctl daemon-reload"
success "Đã xóa systemd files"

# ==============================================================================
# PHASE 4: REMOVE WIREGUARD
# ==============================================================================
echo ""
log "━━━ PHASE 4: XÓA WIREGUARD ━━━"

if [ -d /etc/wireguard ]; then
    if [ "$DRY_RUN" != "true" ]; then
        BACKUP_DIR="/root/wireguard-backup-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r /etc/wireguard/* "$BACKUP_DIR/" 2>/dev/null || true
        log "Đã backup WireGuard tại: $BACKUP_DIR"
    fi
    run_cmd "Xóa WireGuard config" "rm -rf /etc/wireguard/*"
    success "Đã xóa WireGuard config"
fi

# ==============================================================================
# PHASE 5: REMOVE CONFIG & DATA
# ==============================================================================
echo ""
log "━━━ PHASE 5: XÓA CONFIG & DATA ━━━"

run_cmd "Xóa config $CONFIG_DIR" "rm -rf $CONFIG_DIR"
run_cmd "Xóa data $DATA_DIR" "rm -rf $DATA_DIR"
run_cmd "Xóa logs $LOG_DIR" "rm -rf $LOG_DIR"
success "Đã xóa config và data"

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${GREEN}║              DRY-RUN HOÀN TẤT - Không có gì bị xóa                  ║${NC}"
else
    echo -e "${GREEN}║              ✅ NODE ĐÃ GỠ CÀI ĐẶT THÀNH CÔNG                       ║${NC}"
fi
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Đã gỡ bỏ:"
echo -e "${GREEN}║${NC}  ├─ WireGuard (wg0)"
echo -e "${GREEN}║${NC}  ├─ Zero Trust Agent"
echo -e "${GREEN}║${NC}  ├─ ZT_ACL firewall chain"
echo -e "${GREEN}║${NC}  └─ Config & log files"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Backup: ${BACKUP_DIR:-N/A}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Để cài đặt lại:"
echo -e "${GREEN}║${NC}  curl -sL .../scripts/node/install.sh | sudo HUB_URL=... ROLE=app bash"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
