#!/bin/bash

echo "=== Deploying to Kubernetes ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'


# === Root Directory 설정 ===
ROOT_DIR="$(cd "$(dirname "$0")/../../" && pwd)"
cd $ROOT_DIR

echo "Using ROOT_DIR: $ROOT_DIR"

# 1. Docker 이미지 빌드
echo -e "\n${YELLOW}1. Building Docker images...${NC}"
docker build -t log-producer:latest ./services/log-producer
docker build -t log-consumer:latest ./services/log-consumer
docker build -t log-aggregator:latest ./services/log-aggregator

# 2. Minikube에 이미지 로드 (로컬 테스트용)
if command -v minikube &> /dev/null; then
    echo -e "\n${YELLOW}2. Loading images to Minikube...${NC}"
    minikube image load log-producer:latest
    minikube image load log-consumer:latest
    minikube image load log-aggregator:latest
fi

echo -e "\n${YELLOW}3. Applying Namespace & Configs (via Kustomize)...${NC}"

# Kustomize로 Namespace, ConfigMap, Secret 등 기본 리소스 우선 적용
kubectl apply -k k8s/base -l "kind in (Namespace, ConfigMap, Secret, PersistentVolumeClaim)"
echo -e "\n${YELLOW}4. Deploying StatefulSets (DB/Kafka)...${NC}"

# DB와 Kafka 먼저 배포 (Kustomize 전체 적용하되, StatefulSet이 먼저 뜨도록 유도)
kubectl apply -k k8s/base
echo "Waiting for MongoDB & Kafka to be ready..."

# sleep 대신 실제로 준비될 때까지 기다림 (타임아웃 설정)
kubectl wait --for=condition=ready pod -l app=mongodb -n log-monitoring --timeout=120s
kubectl wait --for=condition=ready pod -l app=kafka -n log-monitoring --timeout=120s
echo -e "\n${YELLOW}5. Verifying Deployments...${NC}"

# 나머지 애플리케이션들은 이미 'kubectl apply -k'로 생성되었으므로
# DB가 준비되면 알아서 Running 상태로 전환된다.