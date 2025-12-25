# Zero Trust Networking Infrastructure

Build a Zero Trust Network using Ansible, WireGuard, and Docker.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ZERO TRUST NETWORK                              │
│                                                                         │
│    ┌──────────┐      ┌──────────┐      ┌──────────┐                     │
│    │ DB Node  │◄────►│ App Node │◄────►│ Ops Node │                     │
│    │ Postgres │      │   Odoo   │      │Monitoring│                     │
│    └──────────┘      └──────────┘      └──────────┘                     │
│          │                │                  │                          │
│          └────────────────┼──────────────────┘                          │
│                           │                                             │
│                    ┌──────▼──────┐                                      │
│                    │  WireGuard  │                                      │
│                    │   Mesh VPN  │                                      │
│                    │  (Self-host)│                                      │
│                    └─────────────┘                                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## 📁 Directory Structure

```
zero-trust-networking/
├── inventory/
│   ├── hosts.ini.example   # Template (commit lên git)
│   ├── hosts.ini           # IP thực (⚠️ KHÔNG COMMIT)
│   └── group_vars/
│       ├── all.yml.example # Template (commit lên git)
│       └── all.yml         # Secrets (⚠️ KHÔNG COMMIT)
├── roles/
│   ├── common/             # Base packages & config
│   ├── wireguard/          # Self-hosted VPN
│   ├── security/           # UFW, Fail2ban
│   ├── docker/             # Docker Engine
│   ├── postgres-ha/        # PostgreSQL HA
│   └── odoo-app/           # Odoo Application
├── playbooks/
│   ├── site.yml            # Master playbook
│   ├── setup-control-plane.yml  # Setup Hub
│   └── setup-worker-node.yml    # Setup Worker
└── scripts/
    ├── init-config.sh      # Tạo config từ templates
    └── add-peer-to-hub.sh  # Thêm peer vào mesh
```

## 🔐 Security Notes

**⚠️ QUAN TRỌNG:** Các file sau chứa thông tin nhạy cảm, **KHÔNG COMMIT lên Git:**
- `inventory/hosts.ini` - Public IPs, WireGuard keys
- `inventory/group_vars/all.yml` - Hub configuration

Chỉ commit các file `.example` làm template.

## 🚀 Quick Start

### Hub Server (Lần đầu)

```bash
# 1. Clone repo
git clone <your-repo-url> /home/zero-trust-networking
cd /home/zero-trust-networking

# 2. Tạo config từ templates
chmod +x scripts/*.sh
./scripts/init-config.sh

# 3. Chỉnh sửa config với IP thực
vim inventory/hosts.ini
vim inventory/group_vars/all.yml

# 4. Cài đặt prerequisites
chmod +x install_zero_trust_networking.sh
./install_zero_trust_networking.sh

# 3. Setup WireGuard Hub
ansible-playbook playbooks/setup-wireguard.yml
```

### Thêm VPS mới vào mesh (1 lệnh)

```bash
# SSH vào VPS mới và chạy:
curl -sSL https://raw.githubusercontent.com/YOUR_REPO/bootstrap.sh | sudo bash -s -- 10.10.0.10 node-name

# Hoặc sau khi clone repo:
sudo ./bootstrap.sh 10.10.0.10 node-name
```

Script sẽ tự động:
- ✅ Cài Ansible, Git
- ✅ Clone project
- ✅ Setup WireGuard
- ✅ In ra lệnh để chạy trên Hub

### Trên Hub Server (hoàn tất kết nối)

```bash
# Chạy lệnh mà bootstrap.sh in ra:
./scripts/add-peer-to-hub.sh "node-name" "PUBLIC_KEY" "10.10.0.10"
```

## 📋 Playbooks

| Playbook | Mục đích |
|----------|----------|
| `setup-wireguard.yml` | Setup WireGuard Hub |
| `add-wireguard-peer.yml` | Thêm node mới vào mesh |
| `setup-local.yml` | Kiểm tra trạng thái |
| `site.yml` | Deploy toàn bộ infrastructure |

## 🔐 Security Notes

- **NEVER** commit secrets to Git
- Use `ansible-vault` for sensitive data
- All traffic goes through WireGuard (encrypted)
- UFW default policy: DENY incoming
- 100% tự chủ - không phụ thuộc bên thứ 3

## 📚 Commands Reference

```bash
# Kiểm tra syntax
ansible-playbook playbooks/site.yml --syntax-check

# Chạy chỉ với một số roles
ansible-playbook playbooks/site.yml --tags "security,wireguard"

# Chạy chỉ với một nhóm servers
ansible-playbook playbooks/site.yml --limit db_nodes

# Dry-run (không thay đổi gì)
ansible-playbook playbooks/site.yml --check

# Encrypt file với Vault
ansible-vault encrypt inventory/group_vars/all.yml

# Chạy với vault password
ansible-playbook playbooks/site.yml --ask-vault-pass

# Kiểm tra WireGuard status
wg show
```

## 🔒 WireGuard IP Scheme

| Node | WireGuard IP | Role |
|------|--------------|------|
| Hub Server | 10.10.0.1 | Entry point |
| DB Primary | 10.10.0.10 | PostgreSQL master |
| DB Replica | 10.10.0.11 | PostgreSQL replica |
| App 1 | 10.10.0.20 | Odoo node |
| App 2 | 10.10.0.21 | Odoo node |
| Monitoring | 10.10.0.30 | Prometheus/Grafana |

## 📄 License

MIT License
