#!/bin/bash

echo "=== Cleaning up Kubernetes Resources ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

read -p "Delete entire namespace? (yes/no): " -r
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    if command -v helm &> /dev/null; then
        echo -e "\n${YELLOW}Uninstalling Prometheus Stack Helm Release...${NC}"
        helm uninstall prometheus-stack -n log-monitoring 2>/dev/null || echo "Prometheus Stack already deleted or not found."
        
        # kube-state-metrics가 별도로 설치되어 있다면 삭제 (안전을 위해)
        helm uninstall kube-state-metrics -n log-monitoring 2>/dev/null || true
    fi

    echo -e "\n${YELLOW}Deleting namespace log-monitoring...${NC}"
    kubectl delete namespace log-monitoring
    echo -e "${GREEN}✅ Cleanup completed${NC}"
else
    echo "Aborted."
fi
