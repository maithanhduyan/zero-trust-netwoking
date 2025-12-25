#!/bin/bash

#===============================================================================
#
#          FILE: install_zero_trust_networking.sh
#
#         USAGE: ./install_zero_trust_networking.sh
#
#   DESCRIPTION: Tự động cài đặt môi trường Zero Trust Networking
#                Bao gồm: Ansible, WireGuard, Docker
#                100% tự chủ - Không phụ thuộc bên thứ 3
#
#        AUTHOR: Zero Trust Infrastructure Team
#       CREATED: 2025-12-25
#       VERSION: 1.0.0
#
#===============================================================================

set -e  # Dừng script nếu có lỗi

#-------------------------------------------------------------------------------
# COLORS & FORMATTING
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

#-------------------------------------------------------------------------------
# CONFIGURATION
#-------------------------------------------------------------------------------
PROJECT_DIR="/home/zero-trust-netwoking"
SUDO=""

#-------------------------------------------------------------------------------
# FUNCTIONS
#-------------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}     ZERO TRUST NETWORKING - 100% TỰ CHỦ (WireGuard)            ${NC}${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}[STEP]${NC} ${BOLD}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Đang chạy với quyền root"
        SUDO=""
    else
        SUDO="sudo"
    fi
}

check_ubuntu() {
    if ! command -v lsb_release &> /dev/null; then
        print_error "Không phải Ubuntu/Debian system!"
        exit 1
    fi
    
    DISTRO=$(lsb_release -is)
    VERSION=$(lsb_release -rs)
    
    print_info "Detected: ${DISTRO} ${VERSION}"
}

#-------------------------------------------------------------------------------
# STEP 1: PREREQUISITES
#-------------------------------------------------------------------------------
install_prerequisites() {
    print_step "1/4 - Cập nhật hệ thống và cài đặt prerequisites"
    
    print_info "Updating package lists..."
    ${SUDO} apt-get update -qq
    
    print_info "Installing prerequisites..."
    ${SUDO} apt-get install -y -qq \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        python3 \
        python3-pip \
        python3-venv \
        sshpass \
        jq \
        unzip \
        wget \
        tree
    
    print_success "Prerequisites installed!"
}

#-------------------------------------------------------------------------------
# STEP 2: INSTALL ANSIBLE
#-------------------------------------------------------------------------------
install_ansible() {
    print_step "2/4 - Cài đặt Ansible"
    
    if command -v ansible &> /dev/null; then
        ANSIBLE_VERSION=$(ansible --version | head -n1)
        print_warning "Ansible already installed: ${ANSIBLE_VERSION}"
        return 0
    fi
    
    print_info "Adding Ansible PPA repository..."
    ${SUDO} add-apt-repository --yes --update ppa:ansible/ansible
    
    print_info "Installing Ansible..."
    ${SUDO} apt-get install -y -qq ansible
    
    ANSIBLE_VERSION=$(ansible --version | head -n1)
    print_success "Ansible installed: ${ANSIBLE_VERSION}"
}

#-------------------------------------------------------------------------------
# STEP 3: INSTALL DOCKER
#-------------------------------------------------------------------------------
install_docker() {
    print_step "3/4 - Cài đặt Docker Engine"
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        print_warning "Docker already installed: ${DOCKER_VERSION}"
        return 0
    fi
    
    print_info "Adding Docker GPG key..."
    ${SUDO} install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg
    
    print_info "Adding Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        ${SUDO} tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    print_info "Installing Docker Engine..."
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    if [[ $EUID -ne 0 ]]; then
        print_info "Adding current user to docker group..."
        ${SUDO} usermod -aG docker $USER
    fi
    
    ${SUDO} systemctl enable docker 2>/dev/null || true
    ${SUDO} systemctl start docker 2>/dev/null || true
    
    print_success "Docker installed successfully!"
}

#-------------------------------------------------------------------------------
# STEP 4: INSTALL WIREGUARD
#-------------------------------------------------------------------------------
install_wireguard() {
    print_step "4/4 - Cài đặt WireGuard (Self-hosted VPN)"
    
    if command -v wg &> /dev/null; then
        print_warning "WireGuard already installed"
        return 0
    fi
    
    print_info "Installing WireGuard..."
    ${SUDO} apt-get install -y -qq wireguard wireguard-tools
    
    print_info "Enabling IP forwarding..."
    echo "net.ipv4.ip_forward=1" | ${SUDO} tee /etc/sysctl.d/99-wireguard.conf > /dev/null
    echo "net.ipv6.conf.all.forwarding=1" | ${SUDO} tee -a /etc/sysctl.d/99-wireguard.conf > /dev/null
    ${SUDO} sysctl -p /etc/sysctl.d/99-wireguard.conf 2>/dev/null || true
    
    print_success "WireGuard installed!"
}

#-------------------------------------------------------------------------------
# SUMMARY
#-------------------------------------------------------------------------------
show_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${BOLD}✅ CÀI ĐẶT THÀNH CÔNG!${NC}                        ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}Các công cụ đã được cài đặt:${NC}"
    echo ""
    
    if command -v ansible &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Ansible:    $(ansible --version 2>/dev/null | head -n1 | awk '{print $NF}' | tr -d ']')"
    fi
    
    if command -v docker &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Docker:     $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    fi
    
    if command -v wg &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} WireGuard:  Installed (self-hosted VPN)"
    fi
    
    echo ""
    echo -e "${CYAN}Cấu trúc thư mục:${NC}"
    echo -e "  ${PROJECT_DIR}/"
    echo ""
    
    if command -v tree &> /dev/null; then
        tree -L 2 --dirsfirst "${PROJECT_DIR}/roles" 2>/dev/null || true
    fi
    
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}BƯỚC TIẾP THEO:${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}1.${NC} Cấu hình WireGuard VPN:"
    echo -e "     ${CYAN}cd ${PROJECT_DIR}${NC}"
    echo -e "     ${CYAN}ansible-playbook playbooks/setup-wireguard.yml${NC}"
    echo ""
    echo -e "  ${BOLD}2.${NC} Kiểm tra cài đặt:"
    echo -e "     ${CYAN}ansible-playbook playbooks/setup-local.yml${NC}"
    echo ""
    echo -e "  ${BOLD}3.${NC} Kiểm tra WireGuard status:"
    echo -e "     ${CYAN}wg show${NC}"
    echo ""
    echo -e "  ${BOLD}4.${NC} Deploy lên các servers khác:"
    echo -e "     ${CYAN}ansible-playbook playbooks/site.yml${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
main() {
    print_header
    check_root
    check_ubuntu
    
    install_prerequisites
    install_ansible
    install_docker
    install_wireguard
    
    show_summary
}

main "$@"
