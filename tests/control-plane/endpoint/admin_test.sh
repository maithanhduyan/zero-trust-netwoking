#!/bin/bash
# tests/control-plane/endpoint/admin_test.sh
echo "=== Test Admin List Nodes ===" && \
curl -s http://127.0.0.1:8000/api/v1/admin/nodes \
  -H "X-Admin-Token: change-me-admin-secret" | jq .

echo -e "\n=== Test Create Policy ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/admin/policies \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: change-me-admin-secret" \
  -d '{"name": "allow-app-to-db", "src_role": "app", "dst_role": "db", "port": 5432, "protocol": "tcp", "action": "ACCEPT"}' | jq .

echo -e "\n=== Test Config After Policy ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/postgres-01" | jq .

#
echo "=== Test Create Policy ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/admin/policies \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: change-me-admin-secret" \
  -d '{"name": "allow-app-to-db", "src_role": "app", "dst_role": "db", "port": 5432, "protocol": "tcp", "action": "ACCEPT"}' | jq .


# Policy
echo "=== List Policies ===" && \
curl -s http://127.0.0.1:8000/api/v1/admin/policies \
  -H "X-Admin-Token: change-me-admin-secret" | jq .

echo -e "\n=== Test Config For DB Node (should have ACL from app) ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/postgres-01" | jq .