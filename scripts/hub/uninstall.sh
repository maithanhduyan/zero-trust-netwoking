#!/bin/bash
# ==============================================================================
# ZERO TRUST NETWORK - HUB UNINSTALLER (Production)
# Removes Control Plane and WireGuard Hub completely
# ==============================================================================
#
# Usage:
#   sudo ./uninstall.sh              # Interactive mode
#   sudo ./uninstall.sh --force      # Skip confirmations
#   sudo ./uninstall.sh --dry-run    # Preview only
#   sudo ./uninstall.sh --keep-keys  # Keep WireGuard keys for reinstall
#
# ==============================================================================

set -e

# Configuration paths
INSTALL_DIR="/opt/zero-trust"
CONFIG_DIR="/etc/zero-trust"
DATA_DIR="/var/lib/zero-trust"
LOG_DIR="/var/log/zero-trust"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓${NC} $1"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $1"; }

# Parse arguments
FORCE=false
DRY_RUN=false
KEEP_KEYS=false
for arg in "$@"; do
    case $arg in
        --force|-f) FORCE=true ;;
        --dry-run|-n) DRY_RUN=true ;;
        --keep-keys|-k) KEEP_KEYS=true ;;
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
echo -e "${RED}║              ⚠️  ZERO TRUST HUB UNINSTALLER                          ║${NC}"
echo -e "${RED}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  Sẽ xóa:                                                             ║${NC}"
echo -e "${RED}║  • Control Plane API service và systemd unit                         ║${NC}"
echo -e "${RED}║  • WireGuard Hub (wg0) và cấu hình                                   ║${NC}"
echo -e "${RED}║  • Database và tất cả node registrations                             ║${NC}"
echo -e "${RED}║  • Log files và config files                                         ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Confirmation
if [ "$FORCE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
    echo -e "${YELLOW}⚠️  CẢNH BÁO: Tất cả nodes sẽ mất kết nối với Hub!${NC}"
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

# Kill any running uvicorn processes
if pgrep -f "uvicorn.*main:app" >/dev/null 2>&1; then
    run_cmd "Dừng uvicorn processes" "pkill -f 'uvicorn.*main:app'"
    success "Đã dừng uvicorn"
fi

# Stop Control Plane service
if systemctl is-active --quiet zero-trust-control-plane 2>/dev/null; then
    run_cmd "Dừng Control Plane service" "systemctl stop zero-trust-control-plane"
    success "Đã dừng Control Plane"
fi

if systemctl is-enabled --quiet zero-trust-control-plane 2>/dev/null; then
    run_cmd "Disable Control Plane service" "systemctl disable zero-trust-control-plane"
fi

# Stop WireGuard
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
    run_cmd "Dừng WireGuard" "systemctl stop wg-quick@wg0"
    success "Đã dừng WireGuard"
fi

if systemctl is-enabled --quiet wg-quick@wg0 2>/dev/null; then
    run_cmd "Disable WireGuard" "systemctl disable wg-quick@wg0"
fi

# ==============================================================================
# PHASE 2: REMOVE SYSTEMD FILES
# ==============================================================================
echo ""
log "━━━ PHASE 2: XÓA SYSTEMD FILES ━━━"

run_cmd "Xóa Control Plane service file" "rm -f /etc/systemd/system/zero-trust-control-plane.service"
run_cmd "Reload systemd" "systemctl daemon-reload"
success "Đã xóa systemd files"

# ==============================================================================
# PHASE 3: BACKUP & REMOVE WIREGUARD
# ==============================================================================
echo ""
log "━━━ PHASE 3: WIREGUARD ━━━"

if [ -d /etc/wireguard ]; then
    if [ "$DRY_RUN" != "true" ]; then
        BACKUP_DIR="/root/wireguard-backup-$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp -r /etc/wireguard/* "$BACKUP_DIR/" 2>/dev/null || true
        log "Đã backup WireGuard tại: $BACKUP_DIR"
    fi
    
    if [ "$KEEP_KEYS" = "true" ]; then
        run_cmd "Xóa WireGuard config (giữ keys)" "rm -f /etc/wireguard/wg0.conf"
        log "Đã giữ lại keys trong /etc/wireguard/"
    else
        run_cmd "Xóa tất cả WireGuard config" "rm -rf /etc/wireguard/*"
    fi
    success "Đã xử lý WireGuard config"
fi

# ==============================================================================
# PHASE 4: REMOVE APPLICATION DATA
# ==============================================================================
echo ""
log "━━━ PHASE 4: XÓA DỮ LIỆU ỨNG DỤNG ━━━"

# Remove install directory
if [ -d "$INSTALL_DIR" ]; then
    run_cmd "Xóa thư mục cài đặt $INSTALL_DIR" "rm -rf $INSTALL_DIR"
    success "Đã xóa $INSTALL_DIR"
fi

# Also check legacy paths
for legacy_dir in "/home/zero-trust-netwoking" "/home/zero-trust-networking"; do
    if [ -d "$legacy_dir" ]; then
        run_cmd "Xóa legacy directory $legacy_dir" "rm -rf $legacy_dir"
    fi
done

# Remove config directory
if [ -d "$CONFIG_DIR" ]; then
    run_cmd "Xóa config $CONFIG_DIR" "rm -rf $CONFIG_DIR"
fi

# Remove data directory
if [ -d "$DATA_DIR" ]; then
    run_cmd "Xóa data $DATA_DIR" "rm -rf $DATA_DIR"
fi

# Remove log directory
if [ -d "$LOG_DIR" ]; then
    run_cmd "Xóa logs $LOG_DIR" "rm -rf $LOG_DIR"
fi

# Remove ztctl
run_cmd "Xóa ztctl CLI" "rm -f /usr/local/bin/ztctl"
run_cmd "Xóa ztctl config" "rm -rf /etc/zerotrust"

# Remove logrotate config
run_cmd "Xóa logrotate config" "rm -f /etc/logrotate.d/zero-trust"

success "Đã xóa dữ liệu ứng dụng"

# ==============================================================================
# PHASE 5: CLEANUP IPTABLES
# ==============================================================================
echo ""
log "━━━ PHASE 5: DỌN IPTABLES ━━━"

run_cmd "Xóa FORWARD rules cho wg0" "iptables -D FORWARD -i wg0 -j ACCEPT"
run_cmd "Xóa FORWARD rules cho wg0" "iptables -D FORWARD -o wg0 -j ACCEPT"
run_cmd "Xóa NAT MASQUERADE" "iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
run_cmd "Xóa NAT MASQUERADE ens3" "iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE"

success "Đã dọn iptables"

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${GREEN}║              DRY-RUN HOÀN TẤT - Không có gì bị xóa                  ║${NC}"
else
    echo -e "${GREEN}║              ✅ HUB ĐÃ GỠ CÀI ĐẶT THÀNH CÔNG                        ║${NC}"
fi
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Đã gỡ bỏ:"
echo -e "${GREEN}║${NC}  ├─ Control Plane service"
echo -e "${GREEN}║${NC}  ├─ WireGuard Hub (wg0)"
echo -e "${GREEN}║${NC}  ├─ Database & node registrations"
echo -e "${GREEN}║${NC}  ├─ Log files"
echo -e "${GREEN}║${NC}  └─ ztctl CLI"
echo -e "${GREEN}║${NC}"
if [ "$KEEP_KEYS" = "true" ]; then
    echo -e "${GREEN}║${NC}  ${YELLOW}Đã giữ lại WireGuard keys trong /etc/wireguard/${NC}"
    echo -e "${GREEN}║${NC}"
fi
echo -e "${GREEN}║${NC}  Backup WireGuard: ${BACKUP_DIR:-N/A}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Để cài đặt lại:"
echo -e "${GREEN}║${NC}  curl -sL .../scripts/hub/install.sh | sudo bash"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
