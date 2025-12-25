# =============================================================================
# SETUP BAN ĐẦU
# =============================================================================
# Chạy script này để tạo files cấu hình từ templates
# =============================================================================

echo "🔧 Tạo files cấu hình từ templates..."

# Tạo hosts.ini nếu chưa có
if [ ! -f "inventory/hosts.ini" ]; then
    cp inventory/hosts.ini.example inventory/hosts.ini
    echo "✅ Đã tạo inventory/hosts.ini"
    echo "   → Cập nhật IP và public keys trong file này"
else
    echo "⏭️  inventory/hosts.ini đã tồn tại"
fi

# Tạo all.yml nếu chưa có
if [ ! -f "inventory/group_vars/all.yml" ]; then
    cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
    echo "✅ Đã tạo inventory/group_vars/all.yml"
    echo "   → Cập nhật Hub endpoint và public key"
else
    echo "⏭️  inventory/group_vars/all.yml đã tồn tại"
fi

echo ""
echo "📝 Tiếp theo:"
echo "   1. Chỉnh sửa inventory/hosts.ini với IP servers thực"
echo "   2. Chỉnh sửa inventory/group_vars/all.yml với Hub info"
echo "   3. Chạy: ansible-playbook playbooks/setup-control-plane.yml"
