#!/bin/bash
# tests/control-plane/endpoint/register_test.sh
echo "=== Test Registration ===" && curl -s -X POST http://127.0.0.1:8000/api/v1/agent/register \
  -H "Content-Type: application/json" \
  -d '{"hostname": "test-node-01", "role": "app", "public_key": "aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9dE="}' | jq .


#
echo "=== Test Registration ===" && curl -s -X POST http://127.0.0.1:8000/api/v1/agent/register \
  -H "Content-Type: application/json" \
  -d '{"hostname": "test-node-01", "role": "app", "public_key": "aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9d="}' | jq .


#
sleep 3 && echo "=== Test Registration ===" && curl -s -X POST http://127.0.0.1:8000/api/v1/agent/register \
  -H "Content-Type: application/json" \
  -d '{"hostname": "test-node-01", "role": "app", "public_key": "aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9d="}' | jq .

#
echo "=== Test Register Node 2 (DB role) ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/agent/register \
  -H "Content-Type: application/json" \
  -d '{"hostname": "postgres-01", "role": "db", "public_key": "xY2zE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5zA7bC9d="}' | jq .

echo -e "\n=== Test Get Config ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/test-node-01" | jq .

echo -e "\n=== Test Heartbeat ===" && \
curl -s -X POST http://127.0.0.1:8000/api/v1/agent/heartbeat/test-node-01 | jq .

echo -e "\n=== Test Admin List Nodes ===" && \
curl -s http://127.0.0.1:8000/api/v1/admin/nodes \
  -H "X-Admin-Token: change-me-admin-secret" | jq .