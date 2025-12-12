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

# 3. Namespace 생성
echo -e "\n${YELLOW}3. Creating namespace...${NC}"
kubectl apply -f k8s/base/namespace.yaml

# 4. ConfigMap과 Secret 적용
echo -e "\n${YELLOW}4. Applying ConfigMap and Secrets...${NC}"
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/secret.yaml

# 5. MongoDB 배포
echo -e "\n${YELLOW}5. Deploying MongoDB...${NC}"
kubectl apply -f k8s/base/mongodb/statefulset.yaml

echo "Waiting for MongoDB (30 seconds)..."
sleep 60

# 6. Kafka 배포
echo -e "\n${YELLOW}6. Deploying Kafka...${NC}"
kubectl apply -f k8s/base/kafka/statefulset.yaml

echo "Waiting for Kafka (40 seconds)..."
sleep 40

# 7. Consumers 배포
echo -e "\n${YELLOW}7. Deploying Consumers...${NC}"
kubectl apply -f k8s/base/consumers/deployment.yaml

sleep 20

# 8. Producers 배포
echo -e "\n${YELLOW}8. Deploying Producers...${NC}"
kubectl apply -f k8s/base/producers/deployment.yaml

# 9. Aggregator 배포
echo -e "\n${YELLOW}9. Deploying Aggregator...${NC}"
kubectl apply -f k8s/base/aggregator/deployment.yaml

# 10. Grafana 배포
echo -e "\n${YELLOW}10. Deploying Grafana...${NC}"
kubectl apply -f k8s/base/grafana/deployment.yaml

# 11. HPA 적용
echo -e "\n${YELLOW}11. Applying HPA...${NC}"
kubectl apply -f k8s/base/hpa.yaml

# 12. 상태 확인
echo -e "\n${YELLOW}12. Checking deployment status...${NC}"
kubectl get pods -n log-monitoring

echo -e "\n${GREEN}✅ Deployment completed${NC}"
echo ""
echo "Check status with:"
echo "  kubectl get pods -n log-monitoring"
echo "  kubectl get svc -n log-monitoring"
echo "  kubectl get hpa -n log-monitoring"
