#!/bin/bash
# This script tests the agent registration endpoint of the control plane.
set -e
# Test agent registration
echo "Testing agent registration..."

curl -X POST http://localhost:8000/api/v1/agent/register \
-H "Content-Type: application/json" \
-d '{"hostname": "vps-2-db", "role": "db", "public_key": "MOCK_KEY_123"}'
echo "Agent registration test completed."

# 2. Giả lập Agent đăng ký với vai trò khác
curl -X POST http://localhost:8000/api/v1/agent/register \
-H "Content-Type: application/json" \
-d '{"hostname": "vps-2-db", "role": "db", "public_key": "MOCK_KEY_123"}'


# 3. Giả lập Admin duyệt Node:
# Lấy ID node từ bước trên (ví dụ ID=1)
curl -X POST http://localhost:8000/api/v1/admin/nodes/1/approve \
-H "x-admin-token: secret-admin-token"


# 4. Giả lập Admin tạo Policy:

# Cho phép App gọi DB port 5432
curl -X POST http://localhost:8000/api/v1/admin/policies \
-H "x-admin-token: secret-admin-token" \
-H "Content-Type: application/json" \
-d '{"name": "allow-db", "src_role": "app", "dst_role": "db", "port": 5432}'

# 5. Agent lấy cấu hình:
curl "http://localhost:8000/api/v1/agent/config?public_key=MOCK_KEY_123"