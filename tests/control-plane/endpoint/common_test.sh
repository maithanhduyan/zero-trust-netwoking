#!/bin/bash
# tests/control-plane/endpoint/common_test.sh

echo "=== Test Network Stats ===" && \
curl -s http://127.0.0.1:8000/api/v1/admin/network/stats \
  -H "X-Admin-Token: change-me-admin-secret" | jq .

echo -e "\n=== Test Suspend Node ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/admin/nodes/1/suspend \
  -H "X-Admin-Token: change-me-admin-secret" | jq .

echo -e "\n=== Test Get Config (Should Fail - Suspended) ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/test-node-01" | jq .

echo -e "\n=== Test Approve Node ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/admin/nodes/1/approve \
  -H "X-Admin-Token: change-me-admin-secret" | jq .

#
echo "=== Test Suspend Node ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/admin/nodes/1/suspend \
  -H "X-Admin-Token: change-me-admin-secret" | jq .

echo -e "\n=== Test Get Config (Should Fail - Suspended) ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/test-node-01" | jq .

# Nếu Zero Trust đang hoạt động đúng - node bị suspend không thể lấy config. Test thêm approve:
echo "=== Test Get Config (Should Fail - Suspended) ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/test-node-01" | jq .

#
echo "=== Test Approve Node ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/admin/nodes/1/approve \
  -H "X-Admin-Token: change-me-admin-secret" | jq .

echo -e "\n=== Verify Config Works Again ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/test-node-01" | jq '.status, .acl_rules'

#
curl -s "http://127.0.0.1:8000/api/v1/agent/config/test-node-01" | jq '{status, role, acl_rules}'