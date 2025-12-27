#!/bin/bash
# ==============================================================================
# ZERO TRUST NETWORK - HUB UNINSTALLER
# Removes Control Plane and WireGuard Hub
# ==============================================================================
#
# Usage:
#   sudo ./uninstall.sh              # Interactive mode
#   sudo ./uninstall.sh --force      # Skip confirmations
#   sudo ./uninstall.sh --dry-run    # Preview only
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
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
    esac
done

# Banner
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║              ⚠️  ZERO TRUST HUB UNINSTALLER                          ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  This will remove:                                                   ║${NC}"
echo -e "${RED}║  - Control Plane API service                                         ║${NC}"
echo -e "${RED}║  - WireGuard Hub configuration                                       ║${NC}"
echo -e "${RED}║  - Database and all node registrations                               ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Confirmation
if [ "$FORCE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Tất cả nodes sẽ mất kết nối với Hub!${NC}"
    echo ""
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

# Stop Control Plane
if systemctl is-active --quiet zero-trust-control-plane 2>/dev/null; then
    run_cmd "systemctl stop zero-trust-control-plane"
    run_cmd "systemctl disable zero-trust-control-plane 2>/dev/null || true"
    success "Đã dừng Control Plane"
else
    log "Control Plane không chạy"
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
# PHASE 2: REMOVE CONFIGURATION FILES
# ==============================================================================
echo ""
log "Phase 2: Xóa cấu hình..."

# Remove systemd service file
if [ -f /etc/systemd/system/zero-trust-control-plane.service ]; then
    run_cmd "rm -f /etc/systemd/system/zero-trust-control-plane.service"
    run_cmd "systemctl daemon-reload"
    success "Đã xóa systemd service"
fi

# Remove WireGuard config (backup first)
if [ -d /etc/wireguard ]; then
    if [ "$DRY_RUN" != "true" ]; then
        BACKUP_DIR="/root/wireguard-backup-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r /etc/wireguard/* "$BACKUP_DIR/" 2>/dev/null || true
        log "Backup WireGuard config tại: $BACKUP_DIR"
    fi
    run_cmd "rm -rf /etc/wireguard/*"
    success "Đã xóa WireGuard config"
fi

# ==============================================================================
# PHASE 3: REMOVE APPLICATION DATA
# ==============================================================================
echo ""
log "Phase 3: Xóa dữ liệu ứng dụng..."

# Possible install locations
INSTALL_DIRS=(
    "/opt/zero-trust-control-plane"
    "/home/zero-trust-netwoking"
)

for dir in "${INSTALL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        # Remove database
        if [ -f "$dir/control-plane/zerotrust.db" ]; then
            run_cmd "rm -f $dir/control-plane/zerotrust.db"
            success "Đã xóa database"
        fi
        # Remove .env
        if [ -f "$dir/control-plane/.env" ]; then
            run_cmd "rm -f $dir/control-plane/.env"
            success "Đã xóa .env config"
        fi
    fi
done

# ==============================================================================
# PHASE 4: CLEANUP IPTABLES
# ==============================================================================
echo ""
log "Phase 4: Dọn dẹp iptables..."

# Remove WireGuard iptables rules
run_cmd "iptables -D FORWARD -i wg0 -j ACCEPT 2>/dev/null || true"
run_cmd "iptables -D FORWARD -o wg0 -j ACCEPT 2>/dev/null || true"
run_cmd "iptables -D FORWARD -i wg0 -o wg0 -j ACCEPT 2>/dev/null || true"
run_cmd "iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || true"
success "Đã dọn iptables rules"

# ==============================================================================
# PHASE 5: SUMMARY
# ==============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${GREEN}║              DRY-RUN HOÀN TẤT - Không có gì bị xóa                  ║${NC}"
else
    echo -e "${GREEN}║              ✅ HUB ĐÃ ĐƯỢC GỠ CÀI ĐẶT                               ║${NC}"
fi
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                                      ║${NC}"
echo -e "${GREEN}║${NC}  Đã gỡ bỏ:"
echo -e "${GREEN}║${NC}    - Control Plane service"
echo -e "${GREEN}║${NC}    - WireGuard Hub"
echo -e "${GREEN}║${NC}    - Database & cấu hình"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Để cài đặt lại:"
echo -e "${GREEN}║${NC}    curl -sL .../scripts/hub/install.sh | sudo bash"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
