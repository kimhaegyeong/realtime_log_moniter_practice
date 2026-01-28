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

# 1. Minikube Docker 환경 사용 (이미지 복사 과정 제거로 속도 향상)
if command -v minikube &> /dev/null; then
    echo -e "\n${YELLOW}Configuring Docker environment for Minikube...${NC}"
    eval $(minikube -p minikube docker-env)
fi

# 2. Docker 이미지 빌드 (Minikube 내부 데몬 이용)
echo -e "\n${YELLOW}1. Building Docker images directly in Minikube...${NC}"
docker build -t log-producer:latest ./services/log-producer
docker build -t log-consumer:latest ./services/log-consumer
docker build -t log-aggregator:latest ./services/log-aggregator

echo -e "\n${YELLOW}3. Applying Namespace & Configs (via Kustomize)...${NC}"

# Kustomize로 Namespace, ConfigMap, Secret 등 기본 리소스 우선 적용
kubectl apply -k k8s/base -l "kind in (Namespace, ConfigMap, Secret, PersistentVolumeClaim)"


# Helm을 사용하여 kube-state-metrics 배포
echo -e "\n${YELLOW}3-1. Deploying kube-state-metrics via Helm...${NC}"

if command -v helm &> /dev/null; then
    # Helm Repo 추가 (없을 경우에만)
    if ! helm repo list | grep -q "prometheus-community"; then
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    fi
    
    helm repo update > /dev/null

    # kube-prometheus-stack 설치 (경고 메시지 필터링 및 Grafana 활성화)
    # Grafana 활성화로 변경 (User가 이전 단계에서 Grafana 접속 정보를 확인했으므로)
    echo "Installing/Updating Prometheus Stack (suppressing warnings)..."
    helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace log-monitoring \
        --create-namespace \
        --set grafana.enabled=true \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        2>&1 | grep -vE "unrecognized format|spec.SessionAffinity"
else
    echo -e "${RED}Warning: Helm is not installed. Skipping Prometheus Stack deployment.${NC}"
fi

echo -e "\n${YELLOW}4. Deploying StatefulSets (DB/Kafka)...${NC}"

# DB와 Kafka 먼저 배포
kubectl apply -k k8s/base

echo "Waiting for pods to be created..."
sleep 5  # Pod 생성 대기

# DB 준비 대기
echo "Waiting for MongoDB to be ready..."
kubectl wait --for=condition=ready pod -l app=mongodb -n log-monitoring --timeout=300s

echo -e "\n${YELLOW}5. Verifying Deployments...${NC}"
kubectl get pods -n log-monitoring