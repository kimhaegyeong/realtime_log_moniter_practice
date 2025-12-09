#!/bin/bash

echo "=== Capturing Grafana Dashboard Screenshots ==="

# Grafana Render API 사용
GRAFANA_URL="http://localhost:3000"
AUTH="admin:admin123"

# 대시보드 렌더링
curl -u $AUTH \
    "${GRAFANA_URL}/render/d/log-monitoring/log-monitoring-dashboard?orgId=1&width=1920&height=1080" \
    -o dashboard-screenshot.png

echo "Screenshot saved: dashboard-screenshot.png"
