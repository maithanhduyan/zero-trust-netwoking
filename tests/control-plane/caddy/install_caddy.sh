#!/bin/bash

# Dừng script nếu có lỗi xảy ra
set -e

echo "=== Bắt đầu cài đặt Caddy ==="

echo "[1/6] Cài đặt các gói phụ thuộc..."
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

echo "[2/6] Thêm GPG key của Caddy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

echo "[3/6] Thêm repository Caddy vào source list..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

echo "[4/6] Cập nhật quyền truy cập cho keyring và source list..."
sudo chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
sudo chmod o+r /etc/apt/sources.list.d/caddy-stable.list

echo "[5/6] Cập nhật danh sách gói (apt update)..."
sudo apt update

echo "[6/6] Cài đặt Caddy..."
sudo apt install -y caddy

echo "=== Cài đặt Caddy hoàn tất! ==="
echo "Kiểm tra trạng thái: sudo systemctl status caddy"