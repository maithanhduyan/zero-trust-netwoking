# WireGuard Mesh Network - Hướng Dẫn Chi Tiết

## 📋 Tổng Quan

Hệ thống sử dụng WireGuard VPN tự host để tạo mạng Zero Trust giữa các VPS.

### Topology

```
                    ┌─────────────────────────────────────┐
                    │           INTERNET                  │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │         HUB SERVER                  │
                    │   Public: 5.104.82.252              │
                    │   WireGuard: 10.10.0.1              │
                    │   Port: 51820/UDP                   │
                    └──────────────┬──────────────────────┘
                                   │
          ┌────────────────────────┼────────────────────────┐
          │                        │                        │
    ┌─────▼─────┐            ┌─────▼─────┐            ┌─────▼─────┐
    │ db-primary│            │ db-replica│            │ odoo-app  │
    │ 10.10.0.10│◄──────────►│ 10.10.0.11│            │ 10.10.0.20│
    │ PostgreSQL│  sync      │ PostgreSQL│            │ Odoo      │
    └───────────┘            └───────────┘            └───────────┘
```

### IP Ranges

| Range | Purpose |
|-------|---------|
| 10.10.0.1 | Hub Server |
| 10.10.0.10-19 | Database nodes |
| 10.10.0.20-29 | Application nodes |
| 10.10.0.30-39 | Monitoring nodes |
| 10.10.0.100+ | Additional nodes |

---

## 🚀 Thêm VPS Mới Vào Mesh

### Phương Pháp 1: Script Tự Động (Khuyến nghị)

#### Bước 1: Trên VPS mới

```bash
# SSH vào VPS mới
ssh root@NEW_VPS_IP

# Tải và chạy script
curl -sSL https://raw.githubusercontent.com/your-repo/scripts/quick-peer-setup.sh -o quick-peer-setup.sh
chmod +x quick-peer-setup.sh

# Chạy với IP WireGuard và tên node
./quick-peer-setup.sh 10.10.0.10 db-primary
```

Script sẽ:
- Cài đặt WireGuard
- Generate keys
- Cấu hình kết nối đến Hub
- In ra public key để thêm vào Hub

#### Bước 2: Trên Hub Server

```bash
# SSH vào Hub
ssh root@5.104.82.252

# Chạy script thêm peer (thay thế bằng thông tin thực tế)
cd /home/zero-trust-netwoking
./scripts/add-peer-to-hub.sh "db-primary" "PEER_PUBLIC_KEY" "10.10.0.10"
```

#### Bước 3: Verify kết nối

```bash
# Từ Hub
ping 10.10.0.10

# Từ Peer
ping 10.10.0.1
```

---

### Phương Pháp 2: Sử Dụng Ansible Playbook

#### Bước 1: Trên VPS mới

```bash
# Clone repo
git clone https://github.com/your-repo/zero-trust-networking.git
cd zero-trust-networking

# Chạy playbook
ansible-playbook playbooks/add-wireguard-peer.yml \
  -e "wg_address=10.10.0.10" \
  -e "wg_peer_name=db-primary" \
  -e "wg_hub_endpoint=5.104.82.252" \
  -e "wg_hub_public_key=9c7Sd43PyenG33LjKho0TKykNCJbqgXwhJHRF0jloEs="
```

#### Bước 2: Thêm peer vào Hub (theo hướng dẫn output)

---

### Phương Pháp 3: Manual

#### Trên VPS mới

```bash
# 1. Cài đặt WireGuard
apt update && apt install -y wireguard

# 2. Generate keys
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
chmod 600 /etc/wireguard/private.key

# 3. Tạo config
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/private.key)
Address = 10.10.0.10/24

[Peer]
# Hub Server
PublicKey = 9c7Sd43PyenG33LjKho0TKykNCJbqgXwhJHRF0jloEs=
Endpoint = 5.104.82.252:51820
AllowedIPs = 10.10.0.0/24
PersistentKeepalive = 25
EOF

# 4. Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# 5. Hiển thị public key
cat /etc/wireguard/public.key
```

#### Trên Hub Server

```bash
# 1. Thêm peer vào config
cat >> /etc/wireguard/wg0.conf << EOF

[Peer]
# db-primary
PublicKey = PEER_PUBLIC_KEY_HERE
AllowedIPs = 10.10.0.10/32
EOF

# 2. Apply config (không cần restart)
wg syncconf wg0 <(wg-quick strip wg0)

# 3. Verify
wg show wg0
ping 10.10.0.10
```

---

## 📊 Quản Lý WireGuard

### Xem trạng thái

```bash
# Xem tất cả peers
wg show wg0

# Xem chi tiết
wg show wg0 dump

# Xem interfaces
ip addr show wg0
```

### Xem peers đang kết nối

```bash
wg show wg0 latest-handshakes
```

### Reload config (không ngắt kết nối)

```bash
wg syncconf wg0 <(wg-quick strip wg0)
```

### Restart WireGuard

```bash
systemctl restart wg-quick@wg0
```

### Remove peer

```bash
# Tạm thời (mất khi restart)
wg set wg0 peer PEER_PUBLIC_KEY remove

# Vĩnh viễn - xóa khỏi config file
vim /etc/wireguard/wg0.conf
# Xóa block [Peer] tương ứng
wg syncconf wg0 <(wg-quick strip wg0)
```

---

## 🔧 Troubleshooting

### Peer không kết nối được

1. **Kiểm tra firewall:**
   ```bash
   # Trên Hub
   ufw status
   ufw allow 51820/udp
   ```

2. **Kiểm tra port mở:**
   ```bash
   # Trên Hub
   ss -ulnp | grep 51820
   ```

3. **Kiểm tra handshake:**
   ```bash
   wg show wg0 latest-handshakes
   # Nếu "0 seconds ago" = kết nối OK
   # Nếu không có = chưa kết nối
   ```

4. **Kiểm tra routing:**
   ```bash
   ip route | grep wg0
   ```

### Không ping được giữa các peers

1. **Kiểm tra AllowedIPs:**
   - Hub phải có `AllowedIPs = PEER_IP/32` cho mỗi peer
   - Peer phải có `AllowedIPs = 10.10.0.0/24` để route tất cả traffic qua Hub

2. **Kiểm tra IP forwarding:**
   ```bash
   cat /proc/sys/net/ipv4/ip_forward
   # Phải là 1
   ```

3. **Kiểm tra NAT (nếu peer behind NAT):**
   ```bash
   # Đảm bảo có PersistentKeepalive = 25
   ```

### Debug logs

```bash
# Enable debug
echo module wireguard +p > /sys/kernel/debug/dynamic_debug/control

# Xem logs
dmesg | grep wireguard
journalctl -u wg-quick@wg0 -f
```

---

## 📁 File Structure

```
/etc/wireguard/
├── wg0.conf         # Main configuration
├── private.key      # Private key (chmod 600)
└── public.key       # Public key (share this)

/home/zero-trust-netwoking/
├── scripts/
│   ├── add-peer-to-hub.sh      # Chạy trên Hub để thêm peer
│   └── quick-peer-setup.sh     # Chạy trên VPS mới
├── playbooks/
│   ├── add-wireguard-peer.yml  # Ansible playbook cho peer
│   └── setup-wireguard.yml     # Setup Hub server
└── inventory/
    ├── hosts.ini               # Danh sách servers
    └── group_vars/all.yml      # WireGuard peers config
```

---

## 🔐 Security Best Practices

1. **Private keys**: Không bao giờ share, chmod 600
2. **Firewall**: Chỉ mở port 51820/UDP
3. **Services**: Bind services vào WireGuard interface (10.10.0.x)
4. **SSH**: Sau khi WireGuard hoạt động, restrict SSH chỉ từ 10.10.0.0/24
5. **Backup**: Backup private keys an toàn
