#!/bin/bash
echo "=== Test Get Config ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/test-node-01" | jq .

#
echo "=== Test Config For DB Node (should have ACL from app) ===" && \
curl -s "http://127.0.0.1:8000/api/v1/agent/config/postgres-01" | jq .