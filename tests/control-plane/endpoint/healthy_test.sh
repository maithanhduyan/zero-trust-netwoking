#!/bin/bash
sleep 3 && curl -s http://127.0.0.1:8000/health | jq .