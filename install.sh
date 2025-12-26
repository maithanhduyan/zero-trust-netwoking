#!/bin/bash

# ==============================================================================
#  ZERO TRUST PROJECT SCAFFOLDING (UV EDITION)
# ==============================================================================

set -e
PROJECT_NAME="zero-trust-networking"

#!/bin/bash

# ==============================================================================
#  ZERO TRUST CONTROL PLANE - AUTOMATED INSTALLER
#  Repository: https://github.com/maithanhduyan/zero-trust-netwoking
# ==============================================================================

set -e  # Dừng ngay nếu có lỗi xảy ra

# --- CẤU HÌNH MẶC ĐỊNH ---
INSTALL_DIR="/opt/zero-trust-control-plane"
REPO_URL="https://github.com/maithanhduyan/zero-trust-netwoking.git"
BRANCH="main"
COMPOSE_FILE="docker-compose.prod.yml"

# --- MÀU SẮC ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
# =============================================================================

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
║           KHÔNG TIN BẤT KỲ KẾT NỐI NÀO, KỂ CẢ KẾT NỐI BÊN TRONG                    ║
╚════════════════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# --- HÀM HỖ TRỢ ---
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }


print_banner
# --- 1. KIỂM TRA MÔI TRƯỜNG ---
check_environment() {
    log "1. Kiểm tra môi trường..."

    # Kiểm tra quyền Root
    if [ "$(id -u)" -ne 0 ]; then
        error "Script này cần quyền root. Vui lòng chạy với 'sudo'."
    fi


    # Kiểm tra OS (Khuyến nghị Ubuntu/Debian)


    # Cài đặt các gói cơ bản cần thiết
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y curl git openssl >/dev/null 2>&1
    success "Môi trường đã sẵn sàng."
}

# Install Ansible
install_ansible() {
    log "Step 1/4: Cài đặt Ansible..."
    if ! command -v ansible &> /dev/null; then
        apt-get install -y -qq software-properties-common
        add-apt-repository -y ppa:ansible/ansible > /dev/null 2>&1
        apt-get update -qq
        apt-get install -y -qq ansible
        print_success "Ansible đã cài đặt"
    else
        print_success "Ansible đã có sẵn"
    fi
}
# --- 2. CÀI ĐẶT DOCKER ---
install_docker() {
    log "Kiểm tra Docker..."

    if ! command -v docker &> /dev/null; then
        warn "Docker chưa được cài đặt. Đang tiến hành cài đặt tự động..."
        curl -fsSL https://get.docker.com | sh
        success "Docker đã được cài đặt thành công."
    else
        success "Docker đã tồn tại: $(docker --version)"
    fi
}

# =============================================================================
# STEP 2: Clone or update repo
# =============================================================================

# --- 3. TẢI / CẬP NHẬT MÃ NGUỒN ---
setup_repository() {
    log "3. Thiết lập mã nguồn..."

    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Thư mục cài đặt đã tồn tại. Đang cập nhật code mới nhất..."
        cd "$INSTALL_DIR"
        git fetch origin
        git reset --hard "origin/$BRANCH"
        success "Đã cập nhật mã nguồn."
    elif [ -d "$INSTALL_DIR" ]; then
        error "Thư mục $INSTALL_DIR đã tồn tại nhưng không phải Git repo. Vui lòng xóa thủ công hoặc backup."
    else
        log "Đang clone repository về $INSTALL_DIR..."
        git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        success "Đã clone mã nguồn thành công."
    fi
}

# --- 4. CẤU HÌNH MÔI TRƯỜNG (.env) ---
configure_env() {
    log "4. Cấu hình biến môi trường..."

    if [ -f ".env" ]; then
        warn "File .env đã tồn tại. Sẽ giữ nguyên cấu hình cũ."
        return
    fi

    echo "--------------------------------------------------"
    echo "Hệ thống cần một số thông tin để thiết lập HTTPS."
    echo "--------------------------------------------------"

    # Lấy IP Public tự động
    PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")

    # Hỏi Domain
    read -p "Nhập Domain của bạn (Nhấn Enter để dùng IP $PUBLIC_IP): " INPUT_DOMAIN
    DOMAIN_NAME=${INPUT_DOMAIN:-$PUBLIC_IP}

    # Hỏi Email (Cần cho Let's Encrypt)
    read -p "Nhập Email quản trị (để đăng ký SSL): " INPUT_EMAIL
    ACME_EMAIL=${INPUT_EMAIL:-"admin@localhost"}

    # Sinh mật khẩu ngẫu nhiên
    log "Đang sinh mật khẩu an toàn..."
    DB_PASSWORD=$(openssl rand -hex 16)
    SECRET_KEY=$(openssl rand -hex 32)

    # Ghi file .env
    cat > .env <<EOF
# --- General Config ---
ENV=production
API_PORT=8000
SECRET_KEY=$SECRET_KEY

# --- Caddy / SSL Config ---
DOMAIN_NAME=$DOMAIN_NAME
ACME_EMAIL=$ACME_EMAIL

# --- Database Config ---
DB_HOST=db
DB_PORT=5432
DB_USER=zt_admin
DB_PASSWORD=$DB_PASSWORD
DB_NAME=zt_control_plane
EOF

    success "Đã tạo file .env mới."
}

# =============================================================================
# STEP 3: Run Ansible playbook
# =============================================================================

deploy_containers() {
    log "5. Triển khai Control Plane..."

    cd "$INSTALL_DIR"

    # Kiểm tra xem file docker-compose production có tồn tại không
    if [ ! -f "$COMPOSE_FILE" ]; then
        error "Không tìm thấy file $COMPOSE_FILE. Repo có thể bị lỗi."
    fi

    log "Đang build và khởi động Containers (Quá trình này có thể mất vài phút)..."

    # Tắt version cũ nếu đang chạy
    docker compose -f "$COMPOSE_FILE" down --remove-orphans >/dev/null 2>&1 || true

    # Chạy version mới
    if docker compose -f "$COMPOSE_FILE" up -d --build; then
        success "Containers đã khởi động thành công."
    else
        error "Lỗi khi khởi động Docker Compose."
    fi
}

show_summary() {
    # Lấy thông tin từ .env
    source .env

    echo ""
    echo "=================================================="
    echo -e "${GREEN}   CÀI ĐẶT CONTROL PLANE HOÀN TẤT! ${NC}"
    echo "=================================================="
    echo -e "📂 Thư mục cài đặt:  ${YELLOW}$INSTALL_DIR${NC}"
    echo -e "🌍 Địa chỉ truy cập: ${YELLOW}https://$DOMAIN_NAME${NC} (hoặc http nếu dùng IP)"
    echo -e "🔑 Database User:    ${YELLOW}$DB_USER${NC}"
    echo -e "🔑 Database Pass:    ${YELLOW}$DB_PASSWORD${NC} (Đã lưu trong .env)"
    echo "--------------------------------------------------"
    echo "Để xem logs hệ thống:"
    echo "  cd $INSTALL_DIR"
    echo "  docker compose -f $COMPOSE_FILE logs -f"
    echo "=================================================="
}

# --- MAIN FLOW ---
echo "=================================================="
echo "   ZERO TRUST INSTALLER - v1.0"
echo "=================================================="

check_environment
#install_ansible
#install_docker
setup_repository
#configure_env
#deploy_containers
#show_summary