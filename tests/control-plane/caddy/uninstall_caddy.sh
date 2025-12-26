#!/bin/bash

echo "=== Bắt đầu gỡ cài đặt Caddy ==="

# 1. Dừng service Caddy trước
if systemctl is-active --quiet caddy; then
    echo "Đang dừng service Caddy..."
    sudo systemctl stop caddy
fi

# 2. Gỡ bỏ package Caddy
echo "Đang gỡ bỏ package Caddy..."
# Sử dụng 'purge' để xóa cả file config mặc định, hoặc 'remove' nếu muốn giữ config
sudo apt purge -y caddy
sudo apt autoremove -y

# 3. Xóa Repository và GPG Key đã thêm vào
echo "Đang xóa Repository và GPG Key..."
if [ -f /etc/apt/sources.list.d/caddy-stable.list ]; then
    sudo rm /etc/apt/sources.list.d/caddy-stable.list
    echo "- Đã xóa sources list."
fi

if [ -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg ]; then
    sudo rm /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    echo "- Đã xóa GPG keyring."
fi

# 4. Cập nhật lại apt để loại bỏ cache cũ
echo "Cập nhật lại danh sách gói..."
sudo apt update

echo "=== Gỡ cài đặt Caddy hoàn tất! ==="