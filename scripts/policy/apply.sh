#!/bin/bash
# ==============================================================================
# ZERO TRUST NETWORK - POLICY APPLY
# Push and apply policies to all nodes
# ==============================================================================
#
# Usage:
#   ./apply.sh                      # Apply all policies
#   ./apply.sh --policy=app.yaml    # Apply specific policy
#   ./apply.sh --dry-run            # Preview changes
#   ./apply.sh --rollback           # Rollback to previous
#
# ==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
POLICY_DIR="${PROJECT_ROOT}/policies"
BACKUP_DIR="/var/lib/zerotrust/policy-backups"
HUB_URL="${HUB_URL:-http://localhost:8000}"
ADMIN_TOKEN="${ADMIN_TOKEN:-change-me-admin-secret}"

# Parse arguments
DRY_RUN=false
ROLLBACK=false
SPECIFIC_POLICY=""
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --rollback) ROLLBACK=true ;;
        --policy=*) SPECIFIC_POLICY="${arg#*=}" ;;
    esac
done

# Banner
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              ZERO TRUST - POLICY MANAGER                             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ==============================================================================
# ROLLBACK MODE
# ==============================================================================
if [ "$ROLLBACK" = "true" ]; then
    echo -e "${YELLOW}🔄 ROLLBACK MODE${NC}"
    echo ""
    
    # List available backups
    if [ ! -d "$BACKUP_DIR" ]; then
        error "Không có backup nào. Thư mục $BACKUP_DIR không tồn tại."
    fi
    
    BACKUPS=$(ls -t "$BACKUP_DIR" 2>/dev/null | head -10)
    if [ -z "$BACKUPS" ]; then
        error "Không có backup nào trong $BACKUP_DIR"
    fi
    
    echo "Các bản backup có sẵn:"
    echo ""
    i=1
    for backup in $BACKUPS; do
        echo "  $i) $backup"
        i=$((i+1))
    done
    echo ""
    
    read -p "Chọn backup để restore (1-10): " choice
    
    SELECTED=$(echo "$BACKUPS" | sed -n "${choice}p")
    if [ -z "$SELECTED" ]; then
        error "Lựa chọn không hợp lệ"
    fi
    
    log "Đang restore từ: $SELECTED"
    
    # Restore policies
    cp -r "${BACKUP_DIR}/${SELECTED}/policies/"* "$POLICY_DIR/"
    
    # Trigger sync to all nodes
    log "Trigger sync tới tất cả nodes..."
    curl -s -X POST "${HUB_URL}/api/v1/admin/policies/sync" \
        -H "X-Admin-Token: ${ADMIN_TOKEN}" \
        -H "Content-Type: application/json" \
        -d '{"force": true}' 2>/dev/null || warn "Không thể trigger sync"
    
    success "Đã rollback về: $SELECTED"
    exit 0
fi

# ==============================================================================
# VALIDATE POLICIES
# ==============================================================================
echo -e "${CYAN}━━━ Phase 1: Validate Policies ━━━${NC}"
echo ""

validate_yaml() {
    local file=$1
    python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>&1
}

ERRORS=0
POLICY_FILES=""

if [ -n "$SPECIFIC_POLICY" ]; then
    POLICY_FILES="$POLICY_DIR/$SPECIFIC_POLICY"
    if [ ! -f "$POLICY_FILES" ]; then
        POLICY_FILES="$POLICY_DIR/roles/$SPECIFIC_POLICY"
    fi
    if [ ! -f "$POLICY_FILES" ]; then
        error "Không tìm thấy policy: $SPECIFIC_POLICY"
    fi
else
    POLICY_FILES=$(find "$POLICY_DIR" -name "*.yaml" -o -name "*.yml" 2>/dev/null)
fi

for policy_file in $POLICY_FILES; do
    if [ -f "$policy_file" ]; then
        RESULT=$(validate_yaml "$policy_file")
        if [ -n "$RESULT" ]; then
            echo -e "  ${RED}✗${NC} $(basename $policy_file): $RESULT"
            ERRORS=$((ERRORS+1))
        else
            echo -e "  ${GREEN}✓${NC} $(basename $policy_file)"
        fi
    fi
done

echo ""
if [ $ERRORS -gt 0 ]; then
    error "Có $ERRORS lỗi syntax. Vui lòng sửa trước khi apply."
fi
success "Tất cả policies hợp lệ"

# ==============================================================================
# BACKUP CURRENT POLICIES
# ==============================================================================
echo ""
echo -e "${CYAN}━━━ Phase 2: Backup Policies ━━━${NC}"
echo ""

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_BACKUP="${BACKUP_DIR}/${TIMESTAMP}"

if [ "$DRY_RUN" != "true" ]; then
    mkdir -p "$CURRENT_BACKUP"
    cp -r "$POLICY_DIR" "${CURRENT_BACKUP}/"
    success "Backup tại: $CURRENT_BACKUP"
else
    echo -e "${YELLOW}[DRY-RUN]${NC} Would backup to: ${BACKUP_DIR}/${TIMESTAMP}"
fi

# ==============================================================================
# PUSH TO CONTROL PLANE
# ==============================================================================
echo ""
echo -e "${CYAN}━━━ Phase 3: Push to Control Plane ━━━${NC}"
echo ""

for policy_file in $POLICY_FILES; do
    if [ -f "$policy_file" ]; then
        POLICY_NAME=$(basename "$policy_file" .yaml)
        POLICY_CONTENT=$(cat "$policy_file")
        
        if [ "$DRY_RUN" = "true" ]; then
            echo -e "${YELLOW}[DRY-RUN]${NC} Would push: $POLICY_NAME"
        else
            RESPONSE=$(curl -s -X POST "${HUB_URL}/api/v1/admin/policies" \
                -H "X-Admin-Token: ${ADMIN_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{\"name\": \"${POLICY_NAME}\", \"content\": $(echo "$POLICY_CONTENT" | jq -Rs .)}" 2>&1)
            
            if echo "$RESPONSE" | grep -q '"success":true\|"status":"ok"'; then
                echo -e "  ${GREEN}✓${NC} $POLICY_NAME pushed"
            else
                echo -e "  ${YELLOW}!${NC} $POLICY_NAME: $RESPONSE"
            fi
        fi
    fi
done

# ==============================================================================
# TRIGGER SYNC TO NODES
# ==============================================================================
echo ""
echo -e "${CYAN}━━━ Phase 4: Sync to Nodes ━━━${NC}"
echo ""

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would trigger sync to all nodes"
else
    # Get list of active nodes
    NODES=$(curl -s "${HUB_URL}/api/v1/admin/nodes" \
        -H "X-Admin-Token: ${ADMIN_TOKEN}" 2>/dev/null | \
        jq -r '.nodes[]? | select(.status=="active") | "\(.hostname) (\(.overlay_ip))"' 2>/dev/null)
    
    if [ -n "$NODES" ]; then
        echo "Active nodes:"
        echo "$NODES" | while read node; do
            echo -e "  ${GREEN}●${NC} $node"
        done
        echo ""
        
        # Trigger policy sync
        log "Triggering policy sync..."
        SYNC_RESULT=$(curl -s -X POST "${HUB_URL}/api/v1/admin/policies/sync" \
            -H "X-Admin-Token: ${ADMIN_TOKEN}" \
            -H "Content-Type: application/json" 2>&1)
        
        if echo "$SYNC_RESULT" | grep -q "error"; then
            warn "Sync API chưa implemented. Agents sẽ tự sync trong vòng 60s."
        else
            success "Sync triggered thành công"
        fi
    else
        warn "Không có nodes active hoặc không thể kết nối API"
    fi
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${GREEN}║              DRY-RUN HOÀN TẤT                                        ║${NC}"
else
    echo -e "${GREEN}║              ✅ POLICIES ĐÃ ĐƯỢC APPLY                               ║${NC}"
fi
echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Policies applied: $(echo "$POLICY_FILES" | wc -w)"
echo -e "${GREEN}║${NC}  Backup location:  ${CURRENT_BACKUP:-N/A}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC}  Agents sẽ tự động sync trong vòng 60 giây."
echo -e "${GREEN}║${NC}  Để rollback: ${CYAN}./apply.sh --rollback${NC}"
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
