#!/bin/bash

echo "=== Cleaning up Kubernetes Resources ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

read -p "Delete entire namespace? (yes/no): " -r
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "\n${YELLOW}Deleting namespace log-monitoring...${NC}"
    kubectl delete namespace log-monitoring
    echo -e "${GREEN}✅ Cleanup completed${NC}"
else
    echo "Aborted."
fi
