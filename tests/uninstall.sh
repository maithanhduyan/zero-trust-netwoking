#!/bin/bash
#===============================================================================
# ZERO TRUST NETWORK - COMPLETE UNINSTALL SCRIPT
#===============================================================================
#
# Script này sẽ xóa TẤT CẢ các cài đặt và đưa Ubuntu về trạng thái nguyên thủy
#
# CẢNH BÁO: Script này sẽ XÓA VĨNH VIỄN:
#   - WireGuard và tất cả cấu hình VPN
#   - Docker và tất cả containers/images
#   - Ansible
#   - Fail2ban
#   - UFW rules
#   - Audit logging
#   - Tất cả files trong /home/zero-trust-networking/
#
# Sử dụng:
#   ./uninstall.sh              # Interactive mode (hỏi xác nhận)
#   ./uninstall.sh --force      # Force mode (không hỏi)
#   ./uninstall.sh --dry-run    # Chỉ hiển thị những gì sẽ xóa
#
#===============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PROJECT_DIR="/home/zero-trust-networking"
PROJECT_DIR_ALT="/home/zero-trust-netwoking"  # Typo version

SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

# Parse arguments
FORCE_MODE=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --force|-f) FORCE_MODE=true ;;
        --dry-run|-n) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force, -f     Skip confirmation prompts"
            echo "  --dry-run, -n   Show what would be removed without removing"
            echo "  --help, -h      Show this help message"
            exit 0
            ;;
    esac
done

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------
log() {
    echo -e "${BLUE}[UNINSTALL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_dry() {
    echo -e "${CYAN}[DRY-RUN]${NC} Would: $1"
}

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        log_dry "$1"
    else
        log "$1"
        eval "$2" 2>/dev/null || true
    fi
}

#-------------------------------------------------------------------------------
# Warning Banner
#-------------------------------------------------------------------------------
print_warning() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                                  ║${NC}"
    echo -e "${RED}║   ⚠️  CẢNH BÁO: SCRIPT NÀY SẼ XÓA TẤT CẢ CÀI ĐẶT!              ║${NC}"
    echo -e "${RED}║                                                                  ║${NC}"
    echo -e "${RED}║   Các thành phần sẽ bị XÓA VĨNH VIỄN:                           ║${NC}"
    echo -e "${RED}║   • WireGuard (VPN mesh network)                                 ║${NC}"
    echo -e "${RED}║   • Docker (tất cả containers, images, volumes)                  ║${NC}"
    echo -e "${RED}║   • Ansible                                                      ║${NC}"
    echo -e "${RED}║   • Fail2ban                                                     ║${NC}"
    echo -e "${RED}║   • UFW Firewall rules                                           ║${NC}"
    echo -e "${RED}║   • Audit logging (auditd)                                       ║${NC}"
    echo -e "${RED}║   • Project directories                                          ║${NC}"
    echo -e "${RED}║                                                                  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Confirmation
#-------------------------------------------------------------------------------
confirm_uninstall() {
    if [ "$FORCE_MODE" = true ]; then
        return 0
    fi
    
    print_warning
    
    echo -e "${YELLOW}Bạn có CHẮC CHẮN muốn tiếp tục? (yes/no)${NC}"
    read -r response
    
    if [ "$response" != "yes" ]; then
        echo "Hủy bỏ. Không có gì bị xóa."
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Nhập 'UNINSTALL' để xác nhận lần cuối:${NC}"
    read -r confirm
    
    if [ "$confirm" != "UNINSTALL" ]; then
        echo "Hủy bỏ. Không có gì bị xóa."
        exit 0
    fi
}

#-------------------------------------------------------------------------------
# 1. Stop and Remove WireGuard
#-------------------------------------------------------------------------------
uninstall_wireguard() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  1. REMOVING WIREGUARD${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Stop WireGuard interface
    if ip link show wg0 &>/dev/null; then
        run_cmd "Stopping WireGuard interface wg0..." "${SUDO} wg-quick down wg0"
    fi
    
    # Disable WireGuard service
    if systemctl is-enabled wg-quick@wg0 &>/dev/null; then
        run_cmd "Disabling WireGuard service..." "${SUDO} systemctl disable wg-quick@wg0"
    fi
    
    # Remove WireGuard configuration
    if [ -d /etc/wireguard ]; then
        run_cmd "Removing WireGuard configuration..." "${SUDO} rm -rf /etc/wireguard"
    fi
    
    # Uninstall WireGuard packages
    if dpkg -l | grep -q wireguard; then
        run_cmd "Uninstalling WireGuard packages..." "${SUDO} apt-get purge -y wireguard wireguard-tools"
    fi
    
    log_success "WireGuard removed"
}

#-------------------------------------------------------------------------------
# 2. Stop and Remove Docker
#-------------------------------------------------------------------------------
uninstall_docker() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  2. REMOVING DOCKER${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if command -v docker &>/dev/null; then
        # Stop all running containers
        if [ "$(docker ps -q 2>/dev/null)" ]; then
            run_cmd "Stopping all Docker containers..." "docker stop \$(docker ps -q)"
        fi
        
        # Remove all containers
        if [ "$(docker ps -aq 2>/dev/null)" ]; then
            run_cmd "Removing all Docker containers..." "docker rm -f \$(docker ps -aq)"
        fi
        
        # Remove all images
        if [ "$(docker images -q 2>/dev/null)" ]; then
            run_cmd "Removing all Docker images..." "docker rmi -f \$(docker images -q)"
        fi
        
        # Remove all volumes
        if [ "$(docker volume ls -q 2>/dev/null)" ]; then
            run_cmd "Removing all Docker volumes..." "docker volume rm -f \$(docker volume ls -q)"
        fi
        
        # Remove all networks (except default)
        run_cmd "Removing Docker networks..." "docker network prune -f"
        
        # Prune everything
        run_cmd "Pruning Docker system..." "docker system prune -af --volumes"
    fi
    
    # Stop Docker service
    if systemctl is-active docker &>/dev/null; then
        run_cmd "Stopping Docker service..." "${SUDO} systemctl stop docker docker.socket containerd"
    fi
    
    # Disable Docker service
    if systemctl is-enabled docker &>/dev/null; then
        run_cmd "Disabling Docker service..." "${SUDO} systemctl disable docker docker.socket containerd"
    fi
    
    # Uninstall Docker packages
    run_cmd "Uninstalling Docker packages..." "${SUDO} apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose podman-docker"
    
    # Remove Docker data directories
    run_cmd "Removing Docker data..." "${SUDO} rm -rf /var/lib/docker /var/lib/containerd /etc/docker"
    
    # Remove Docker apt repository
    run_cmd "Removing Docker apt repository..." "${SUDO} rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg"
    
    log_success "Docker removed"
}

#-------------------------------------------------------------------------------
# 3. Remove Ansible
#-------------------------------------------------------------------------------
uninstall_ansible() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  3. REMOVING ANSIBLE${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Uninstall Ansible
    if command -v ansible &>/dev/null; then
        run_cmd "Uninstalling Ansible..." "${SUDO} apt-get purge -y ansible"
    fi
    
    # Remove Ansible PPA
    run_cmd "Removing Ansible PPA..." "${SUDO} add-apt-repository --remove -y ppa:ansible/ansible"
    run_cmd "Removing Ansible apt list..." "${SUDO} rm -f /etc/apt/sources.list.d/ansible*.list"
    
    # Remove Ansible configuration
    run_cmd "Removing Ansible config..." "${SUDO} rm -rf /etc/ansible ~/.ansible"
    
    log_success "Ansible removed"
}

#-------------------------------------------------------------------------------
# 4. Remove Security Tools
#-------------------------------------------------------------------------------
uninstall_security() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  4. REMOVING SECURITY TOOLS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Stop and remove Fail2ban
    if systemctl is-active fail2ban &>/dev/null; then
        run_cmd "Stopping Fail2ban..." "${SUDO} systemctl stop fail2ban"
    fi
    run_cmd "Uninstalling Fail2ban..." "${SUDO} apt-get purge -y fail2ban"
    run_cmd "Removing Fail2ban config..." "${SUDO} rm -rf /etc/fail2ban"
    
    # Remove auditd
    if systemctl is-active auditd &>/dev/null; then
        run_cmd "Stopping Auditd..." "${SUDO} systemctl stop auditd"
    fi
    run_cmd "Uninstalling Auditd..." "${SUDO} apt-get purge -y auditd audispd-plugins"
    run_cmd "Removing audit rules..." "${SUDO} rm -rf /etc/audit"
    
    # Remove rkhunter and chkrootkit
    run_cmd "Uninstalling security scanners..." "${SUDO} apt-get purge -y rkhunter chkrootkit"
    
    # Remove logwatch
    run_cmd "Uninstalling Logwatch..." "${SUDO} apt-get purge -y logwatch"
    
    # Remove unattended-upgrades
    run_cmd "Uninstalling unattended-upgrades..." "${SUDO} apt-get purge -y unattended-upgrades apt-listchanges"
    run_cmd "Removing auto-upgrade config..." "${SUDO} rm -f /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/50unattended-upgrades"
    
    log_success "Security tools removed"
}

#-------------------------------------------------------------------------------
# 5. Reset UFW Firewall
#-------------------------------------------------------------------------------
reset_firewall() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  5. RESETTING FIREWALL${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if command -v ufw &>/dev/null; then
        run_cmd "Disabling UFW..." "${SUDO} ufw disable"
        run_cmd "Resetting UFW rules..." "${SUDO} ufw --force reset"
    fi
    
    # Option: completely remove UFW
    # run_cmd "Uninstalling UFW..." "${SUDO} apt-get purge -y ufw"
    
    log_success "Firewall reset"
}

#-------------------------------------------------------------------------------
# 6. Reset SSH Configuration
#-------------------------------------------------------------------------------
reset_ssh() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  6. RESETTING SSH CONFIGURATION${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Restore backup if exists
    if [ -f /etc/ssh/sshd_config.backup ]; then
        run_cmd "Restoring SSH config from backup..." "${SUDO} cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config"
    else
        # Reset to defaults
        run_cmd "Resetting SSH to defaults..." "${SUDO} apt-get install --reinstall -y openssh-server"
    fi
    
    # Restart SSH
    run_cmd "Restarting SSH service..." "${SUDO} systemctl restart sshd"
    
    log_success "SSH configuration reset"
}

#-------------------------------------------------------------------------------
# 7. Reset Kernel Parameters
#-------------------------------------------------------------------------------
reset_kernel() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  7. RESETTING KERNEL PARAMETERS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Remove custom sysctl configs
    run_cmd "Removing custom sysctl configs..." "${SUDO} rm -f /etc/sysctl.d/99-zero-trust.conf /etc/sysctl.d/99-security.conf"
    
    # Reload sysctl
    run_cmd "Reloading sysctl defaults..." "${SUDO} sysctl --system"
    
    log_success "Kernel parameters reset"
}

#-------------------------------------------------------------------------------
# 8. Remove Project Directories
#-------------------------------------------------------------------------------
remove_project_dirs() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  8. REMOVING PROJECT DIRECTORIES${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Remove main project directory
    if [ -d "$PROJECT_DIR" ]; then
        run_cmd "Removing $PROJECT_DIR..." "${SUDO} rm -rf $PROJECT_DIR"
    fi
    
    # Remove alternate project directory (typo version)
    if [ -d "$PROJECT_DIR_ALT" ]; then
        run_cmd "Removing $PROJECT_DIR_ALT..." "${SUDO} rm -rf $PROJECT_DIR_ALT"
    fi
    
    log_success "Project directories removed"
}

#-------------------------------------------------------------------------------
# 9. Clean Up Packages
#-------------------------------------------------------------------------------
cleanup_packages() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  9. CLEANING UP PACKAGES${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Remove orphaned packages
    run_cmd "Removing orphaned packages..." "${SUDO} apt-get autoremove -y"
    
    # Clean apt cache
    run_cmd "Cleaning apt cache..." "${SUDO} apt-get autoclean -y"
    
    # Update apt cache
    run_cmd "Updating apt cache..." "${SUDO} apt-get update -qq"
    
    log_success "Package cleanup complete"
}

#-------------------------------------------------------------------------------
# 10. Remove User from Docker Group
#-------------------------------------------------------------------------------
remove_user_groups() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  10. CLEANING UP USER GROUPS${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Remove user from docker group
    if getent group docker &>/dev/null; then
        run_cmd "Removing user from docker group..." "${SUDO} gpasswd -d $USER docker"
        run_cmd "Removing docker group..." "${SUDO} groupdel docker"
    fi
    
    log_success "User groups cleaned"
}

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${GREEN}║   ✅ DRY RUN COMPLETE - Nothing was actually removed            ║${NC}"
    else
        echo -e "${GREEN}║   ✅ UNINSTALL COMPLETE - Ubuntu restored to original state     ║${NC}"
    fi
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║   Đã xóa:                                                        ║${NC}"
    echo -e "${GREEN}║   • WireGuard VPN                                                ║${NC}"
    echo -e "${GREEN}║   • Docker + containers + images                                 ║${NC}"
    echo -e "${GREEN}║   • Ansible                                                      ║${NC}"
    echo -e "${GREEN}║   • Fail2ban, Auditd                                            ║${NC}"
    echo -e "${GREEN}║   • UFW rules (firewall disabled)                                ║${NC}"
    echo -e "${GREEN}║   • Custom SSH config                                            ║${NC}"
    echo -e "${GREEN}║   • Kernel security parameters                                   ║${NC}"
    echo -e "${GREEN}║   • Project directories                                          ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo -e "${YELLOW}⚠️  Khuyến nghị: Reboot hệ thống để hoàn tất${NC}"
        echo ""
        echo -e "   ${SUDO} reboot"
        echo ""
    fi
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------
main() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║        ZERO TRUST NETWORK - COMPLETE UNINSTALL                   ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
    
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo -e "${CYAN}🔍 DRY RUN MODE - Hiển thị những gì sẽ bị xóa${NC}"
        echo ""
    fi
    
    confirm_uninstall
    
    uninstall_wireguard
    uninstall_docker
    uninstall_ansible
    uninstall_security
    reset_firewall
    reset_ssh
    reset_kernel
    remove_project_dirs
    remove_user_groups
    cleanup_packages
    
    print_summary
}

main
