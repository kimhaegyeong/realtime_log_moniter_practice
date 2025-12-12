#!/bin/bash

echo "=== Kubernetes Status ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# === Root Directory 설정 ===
ROOT_DIR="$(cd "$(dirname "$0")/../../" && pwd)"
cd $ROOT_DIR

echo "Using ROOT_DIR: $ROOT_DIR"

echo -e "\n${YELLOW}Pods:${NC}"
kubectl get pods -n log-monitoring -o wide

echo -e "\n${YELLOW}Services:${NC}"
kubectl get svc -n log-monitoring

echo -e "\n${YELLOW}StatefulSets:${NC}"
kubectl get statefulsets -n log-monitoring

echo -e "\n${YELLOW}Deployments:${NC}"
kubectl get deployments -n log-monitoring

echo -e "\n${YELLOW}HPA Status:${NC}"
kubectl get hpa -n log-monitoring

echo -e "\n${YELLOW}PVC Status:${NC}"
kubectl get pvc -n log-monitoring

echo -e "\n${YELLOW}Recent Events:${NC}"
kubectl get events -n log-monitoring --sort-by='.lastTimestamp' | tail -10

echo -e "\n${GREEN}✅ Status check completed${NC}"
