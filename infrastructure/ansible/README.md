# Zero Trust Network - Ansible Deployment

This directory contains Ansible playbooks for deploying the Zero Trust Network infrastructure.

## Directory Structure

```
ansible/
├── ansible.cfg              # Ansible configuration
├── site.yml                 # Main deployment playbook
├── inventory/
│   ├── hosts.ini            # Production inventory
│   ├── local.ini            # Local testing inventory
│   └── group_vars/          # Group variables
│       ├── all.yml          # Global variables
│       ├── hub.yml          # Hub-specific vars
│       ├── app.yml          # App server vars
│       ├── db.yml           # Database server vars
│       └── ops.yml          # Ops server vars
├── playbook/
│   ├── deploy-hub.yml       # Deploy Hub only
│   ├── deploy-agents.yml    # Deploy Agents only
│   ├── sync-policies.yml    # Sync policies only
│   └── test-local.yml       # Local testing
└── roles/
    ├── common/              # Base system setup
    ├── wireguard/           # WireGuard installation
    ├── control-plane/       # Control Plane deployment
    └── agent/               # Agent deployment
```

## Quick Start

### 1. Prerequisites

```bash
# Install Ansible
pip install ansible

# Verify installation
ansible --version
```

### 2. Configure Inventory

Edit `inventory/hosts.ini` with your servers:

```ini
[hub]
hub.example.com ansible_host=YOUR_HUB_IP

[app]
app-01.example.com ansible_host=YOUR_APP_IP

[db]
postgres-01.example.com ansible_host=YOUR_DB_IP
```

### 3. Set Admin Secret

```bash
export ADMIN_SECRET="your-secure-secret-here"
```

### 4. Test Locally First

```bash
ansible-playbook -i inventory/local.ini playbook/test-local.yml
```

### 5. Deploy

```bash
# Full deployment
ansible-playbook -i inventory/hosts.ini site.yml

# Or deploy in phases
ansible-playbook -i inventory/hosts.ini site.yml --tags hub
ansible-playbook -i inventory/hosts.ini site.yml --tags agents
ansible-playbook -i inventory/hosts.ini site.yml --tags policies
ansible-playbook -i inventory/hosts.ini site.yml --tags verify
```

## Deployment Phases

| Phase | Tag | Description |
|-------|-----|-------------|
| 1 | `hub` | Deploy Control Plane + WireGuard Hub |
| 2 | `agents` | Deploy Agents to spoke nodes |
| 3 | `policies` | Sync policy YAML files to database |
| 4 | `verify` | Run health checks and show summary |
| 5 | `test` | Test overlay connectivity (manual) |

## Roles

### common
- Install base packages (curl, wget, git, etc.)
- Configure sysctl for networking
- Setup base firewall rules
- Create ZT directories

### wireguard
- Install WireGuard
- Generate keypair
- Configure interface (hub or spoke)
- Start WireGuard service

### control-plane
- Install uv package manager
- Deploy Control Plane source code
- Create systemd service
- Install Caddy reverse proxy
- Wait for health check

### agent
- Deploy Agent source code
- Register with Control Plane
- Configure WireGuard spoke
- Create systemd service
- Start agent daemon

## Variables

### Global (group_vars/all.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `overlay_network` | 10.0.0.0/24 | Overlay network CIDR |
| `wireguard_port` | 51820 | WireGuard UDP port |
| `admin_secret` | (from env) | Control Plane admin token |
| `auto_approve_nodes` | false | Auto-approve new nodes |

### Per-Host

Set in inventory or host_vars:

```ini
[app]
app-01 ansible_host=1.2.3.4 node_role=app node_description="API Server"
```

## Troubleshooting

### Check connectivity
```bash
ansible all -i inventory/hosts.ini -m ping
```

### View logs on Hub
```bash
ssh hub 'journalctl -u control-plane -f'
```

### View logs on Agent
```bash
ssh app-01 'journalctl -u zt-agent -f'
```

### Check WireGuard status
```bash
ansible hub -i inventory/hosts.ini -a 'wg show'
```

## Security Notes

1. **Never commit** `ADMIN_SECRET` to version control
2. Use **SSH keys** instead of passwords
3. Consider using **Ansible Vault** for sensitive data
4. Review firewall rules before deployment
