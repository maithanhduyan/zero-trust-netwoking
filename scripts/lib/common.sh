#!/bin/bash
# ==============================================================================
# ZERO TRUST NETWORK - SHARED LIBRARY
# Common functions for all scripts
# ==============================================================================

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Print phase header
print_phase() {
    local phase_num=$1
    local phase_name=$2
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} PHASE ${phase_num}: ${phase_name}${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Script phải chạy với quyền root. Sử dụng: sudo $0"
    fi
    success "Đang chạy với quyền root"
}

# Confirm action
confirm() {
    local message="${1:-Bạn có chắc chắn muốn tiếp tục?}"
    echo -e "${YELLOW}${message}${NC}"
    read -p "[y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Get OS info
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$PRETTY_NAME"
    else
        echo "Unknown OS"
    fi
}

# Check if service is running
service_is_running() {
    systemctl is-active --quiet "$1"
}

# Wait for service to start
wait_for_service() {
    local service=$1
    local timeout=${2:-30}
    local count=0
    
    while ! service_is_running "$service"; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            return 1
        fi
    done
    return 0
}

# Get public IPv4
get_public_ipv4() {
    curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
    curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || \
    curl -4 -s --max-time 5 ipv4.icanhazip.com 2>/dev/null || \
    echo ""
}

# Backup file with timestamp
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
}

# Check WireGuard status
wg_is_running() {
    wg show wg0 &>/dev/null
}

# Get WireGuard public key
get_wg_public_key() {
    cat /etc/wireguard/public.key 2>/dev/null || echo ""
}

# Parse YAML value (simple implementation)
yaml_get() {
    local file=$1
    local key=$2
    grep "^${key}:" "$file" 2>/dev/null | cut -d':' -f2- | sed 's/^[ ]*//'
}
