#!bin/bash
# tests/install/new_install_test.sh
curl -s -X POST -H "X-Admin-Token: change-me-admin-secret" -H "Content-Type: application/json" \
  http://localhost:8000/api/v1/admin/wireguard/add-peer \
  -d '{"public_key": "testkey123456789012345678901234567890123=", "allowed_ips": "10.10.0.99/32", "comment": "test-node"}' | python3 -m json.tool
