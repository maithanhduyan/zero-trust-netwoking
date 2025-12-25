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
│   ├── hosts.ini           # Inventory với WireGuard IPs
│   └── group_vars/
│       └── all.yml         # Variables (encrypted)
├── roles/
│   ├── common/             # Base packages & config
│   ├── wireguard/          # Self-hosted VPN (không phụ thuộc bên thứ 3)
│   ├── security/           # UFW, Fail2ban
│   ├── docker/             # Docker Engine
│   ├── postgres-ha/        # PostgreSQL HA
│   └── odoo-app/           # Odoo Application
├── playbooks/
│   ├── site.yml            # Master playbook
│   ├── setup-local.yml     # Local machine setup
│   └── setup-wireguard.yml # WireGuard VPN setup
└── .github/workflows/
    └── validate.yml        # CI/CD validation
```

## 🚀 Quick Start

### 1. Install prerequisites

```bash
chmod +x install_zero_trust_networking.sh
./install_zero_trust_networking.sh
```

### 2. Setup WireGuard VPN

```bash
ansible-playbook playbooks/setup-wireguard.yml
```

### 3. Check local setup

```bash
ansible-playbook playbooks/setup-local.yml
```

### 4. Deploy to all nodes

```bash
ansible-playbook playbooks/site.yml
```

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
