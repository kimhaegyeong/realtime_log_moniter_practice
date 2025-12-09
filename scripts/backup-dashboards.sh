#!/bin/bash

echo "=== Backing up Grafana Dashboards ==="

GRAFANA_URL="http://localhost:3000"
AUTH="admin:admin123"
BACKUP_DIR="monitoring/grafana/backups"

mkdir -p $BACKUP_DIR

# 모든 대시보드 가져오기
DASHBOARDS=$(curl -s -u $AUTH "${GRAFANA_URL}/api/search?type=dash-db")

# 각 대시보드 백업
echo "$DASHBOARDS" | jq -r '.[] | .uid' | while read uid; do
    DASHBOARD=$(curl -s -u $AUTH "${GRAFANA_URL}/api/dashboards/uid/${uid}")
    TITLE=$(echo "$DASHBOARD" | jq -r '.dashboard.title' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    
    echo "$DASHBOARD" | jq '.dashboard' > "${BACKUP_DIR}/${TITLE}-${uid}.json"
    echo "Backed up: ${TITLE}"
done

echo "✅ Backup completed: $BACKUP_DIR"
