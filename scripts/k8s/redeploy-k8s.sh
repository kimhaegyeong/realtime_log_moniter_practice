#!/bin/bash

echo "=== Redeploying to Kubernetes ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 0. 사전 체크
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Kubernetes Redeployment Script        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# 사용자 확인
echo -e "\n${YELLOW}⚠️  This will DELETE all existing resources in log-monitoring namespace${NC}"
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Aborted."
    exit 0
fi

# === Root Directory 설정 ===
ROOT_DIR="$(cd "$(dirname "$0")/../../" && pwd)"
cd $ROOT_DIR

echo "Using ROOT_DIR: $ROOT_DIR"

# 1. 기존 리소스 삭제
echo -e "\n${YELLOW}1. Deleting existing namespace...${NC}"
kubectl delete namespace log-monitoring --ignore-not-found=true

echo "Waiting for namespace deletion (30 seconds)..."
sleep 30

# 2. Docker 이미지 빌드
echo -e "\n${YELLOW}2. Building Docker images...${NC}"
docker build -t log-producer:latest ./services/log-producer
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to build log-producer${NC}"
    exit 1
fi

docker build -t log-consumer:latest ./services/log-consumer
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to build log-consumer${NC}"
    exit 1
fi

docker build -t log-aggregator:latest ./services/log-aggregator
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to build log-aggregator${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All images built successfully${NC}"

# 3. Minikube에 이미지 로드
if command -v minikube &> /dev/null; then
    MINIKUBE_STATUS=$(minikube status --format='{{.Host}}' 2>/dev/null)
    if [ "$MINIKUBE_STATUS" == "Running" ]; then
        echo -e "\n${YELLOW}3. Loading images to Minikube...${NC}"
        minikube image load log-producer:latest
        minikube image load log-consumer:latest
        minikube image load log-aggregator:latest
        echo -e "${GREEN}✅ Images loaded${NC}"
    fi
fi

# 4. Namespace 생성
echo -e "\n${YELLOW}4. Creating namespace...${NC}"
kubectl apply -f k8s/base/namespace.yaml

# 5. ConfigMap과 Secret
echo -e "\n${YELLOW}5. Applying ConfigMap and Secrets...${NC}"
kubectl apply -f k8s/base/configmap.yaml
kubectl apply -f k8s/base/secret.yaml

# 6. MongoDB 배포
echo -e "\n${YELLOW}6. Deploying MongoDB...${NC}"
kubectl apply -f k8s/base/mongodb/statefulset.yaml

echo "Waiting for MongoDB .."
sleep 40

# MongoDB 상태 확인
kubectl wait --for=condition=ready pod -l app=mongodb -n log-monitoring --timeout=60s
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ MongoDB is ready${NC}"
else
    echo -e "${RED}⚠️  MongoDB is not ready yet, but continuing...${NC}"
fi

# 7. Kafka 배포
echo -e "\n${YELLOW}7. Deploying Kafka (Zookeeper + Kafka)...${NC}"
kubectl apply -f k8s/base/kafka/statefulset.yaml

echo "Waiting for Kafka ..."
sleep 60

# Kafka 상태 확인
kubectl wait --for=condition=ready pod -l app=kafka -n log-monitoring --timeout=90s
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Kafka is ready${NC}"
else
    echo -e "${RED}⚠️  Kafka is not ready yet, but continuing...${NC}"
fi

# 8. Consumers 배포
echo -e "\n${YELLOW}8. Deploying Consumers...${NC}"
kubectl apply -f k8s/base/consumers/deployment.yaml

sleep 20

# 9. Producers 배포
echo -e "\n${YELLOW}9. Deploying Producers...${NC}"
kubectl apply -f k8s/base/producers/deployment.yaml

# 10. Aggregator 배포
echo -e "\n${YELLOW}10. Deploying Aggregator...${NC}"
kubectl apply -f k8s/base/aggregator/deployment.yaml

# 11. Grafana 배포
echo -e "\n${YELLOW}11. Deploying Grafana...${NC}"
kubectl apply -f k8s/base/grafana/deployment.yaml

# 12. HPA 적용
echo -e "\n${YELLOW}12. Applying HPA...${NC}"
kubectl apply -f k8s/base/hpa.yaml

# 13. 최종 상태 확인
echo -e "\n${YELLOW}13. Waiting for all pods to be ready (30 seconds)...${NC}"
sleep 30

echo -e "\n${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Deployment Status                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"

kubectl get pods -n log-monitoring

echo -e "\n${BLUE}Services:${NC}"
kubectl get svc -n log-monitoring

echo -e "\n${BLUE}HPA:${NC}"
kubectl get hpa -n log-monitoring

echo -e "\n${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ Redeployment Completed Successfully  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "  1. Check pod status: kubectl get pods -n log-monitoring -w"
echo "  2. Check logs: kubectl logs -f deployment/log-consumer -n log-monitoring"
echo "  3. Access services:"
echo "     - kubectl port-forward svc/log-producer-api 8000:8000 -n log-monitoring"
echo "     - kubectl port-forward svc/log-aggregator 8001:8001 -n log-monitoring"
echo "     - kubectl port-forward svc/grafana 3000:3000 -n log-monitoring"
