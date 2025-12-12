#!/bin/bash

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           TASK-9 Completion Verification                  ║"
echo "║     Kubernetes 매니페스트 작성 및 배포 확인                 ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="log-monitoring"
PASS=0
FAIL=0

check_item() {
    local description=$1
    local command=$2
    
    echo -ne "${YELLOW}Checking: ${description}...${NC}"
    
    if eval "$command" &> /dev/null; then
        echo -e " ${GREEN}✅ PASS${NC}"
        ((PASS++))
        return 0
    else
        echo -e " ${RED}❌ FAIL${NC}"
        ((FAIL++))
        return 1
    fi
}

check_item_with_output() {
    local description=$1
    local command=$2
    local expected=$3
    
    echo -ne "${YELLOW}Checking: ${description}...${NC}"
    
    result=$(eval "$command" 2>/dev/null)
    if [[ $result == *"$expected"* ]]; then
        echo -e " ${GREEN}✅ PASS${NC}"
        echo "  → $result"
        ((PASS++))
        return 0
    else
        echo -e " ${RED}❌ FAIL${NC}"
        echo "  → Expected: $expected"
        echo "  → Got: $result"
        ((FAIL++))
        return 1
    fi
}

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}1. Kubernetes 클러스터 연결 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Kubernetes 클러스터 접근 가능" \
    "kubectl cluster-info"

check_item "Nodes Ready 상태" \
    "kubectl get nodes | grep -q Ready"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}2. Namespace 및 기본 리소스 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Namespace 'log-monitoring' 존재" \
    "kubectl get namespace $NAMESPACE"

check_item "ConfigMap 존재" \
    "kubectl get configmap log-monitoring-config -n $NAMESPACE"

check_item "Secret 존재" \
    "kubectl get secret log-monitoring-secrets -n $NAMESPACE"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}3. StatefulSet 배포 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Zookeeper StatefulSet 존재" \
    "kubectl get statefulset zookeeper -n $NAMESPACE"

check_item "Kafka StatefulSet 존재" \
    "kubectl get statefulset kafka -n $NAMESPACE"

check_item "MongoDB StatefulSet 존재" \
    "kubectl get statefulset mongodb -n $NAMESPACE"

check_item "Zookeeper Pod Running" \
    "kubectl get pods -n $NAMESPACE -l app=zookeeper | grep -q Running"

check_item "Kafka Pod Running" \
    "kubectl get pods -n $NAMESPACE -l app=kafka | grep -q Running"

check_item "MongoDB Pod Running" \
    "kubectl get pods -n $NAMESPACE -l app=mongodb | grep -q Running"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}4. Deployment 배포 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Producer API Deployment 존재" \
    "kubectl get deployment log-producer-api -n $NAMESPACE"

check_item "Producer API Service Deployment 존재" \
    "kubectl get deployment producer-api-service -n $NAMESPACE"

check_item "Producer Auth Service Deployment 존재" \
    "kubectl get deployment producer-auth-service -n $NAMESPACE"

check_item "Producer Payment Service Deployment 존재" \
    "kubectl get deployment producer-payment-service -n $NAMESPACE"

check_item "Consumer Deployment 존재" \
    "kubectl get deployment log-consumer -n $NAMESPACE"

check_item "Aggregator Deployment 존재" \
    "kubectl get deployment log-aggregator -n $NAMESPACE"

check_item "Grafana Deployment 존재" \
    "kubectl get deployment grafana -n $NAMESPACE"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}5. Service 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Zookeeper Service 존재" \
    "kubectl get service zookeeper -n $NAMESPACE"

check_item "Kafka Service 존재" \
    "kubectl get service kafka -n $NAMESPACE"

check_item "MongoDB Service 존재" \
    "kubectl get service mongodb -n $NAMESPACE"

check_item "Producer API Service 존재" \
    "kubectl get service log-producer-api -n $NAMESPACE"

check_item "Aggregator Service 존재" \
    "kubectl get service log-aggregator -n $NAMESPACE"

check_item "Grafana Service 존재" \
    "kubectl get service grafana -n $NAMESPACE"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}6. PersistentVolumeClaim 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Zookeeper PVC 존재 및 Bound" \
    "kubectl get pvc -n $NAMESPACE | grep zookeeper | grep -q Bound"

check_item "Kafka PVC 존재 및 Bound" \
    "kubectl get pvc -n $NAMESPACE | grep kafka | grep -q Bound"

check_item "MongoDB PVC 존재 및 Bound" \
    "kubectl get pvc -n $NAMESPACE | grep mongodb | grep -q Bound"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}7. HPA (Horizontal Pod Autoscaler) 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Consumer HPA 존재" \
    "kubectl get hpa log-consumer-hpa -n $NAMESPACE"

check_item "Metrics Server 설치됨" \
    "kubectl get deployment metrics-server -n kube-system"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}8. Pod 상태 상세 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

echo -e "${YELLOW}All Pods in namespace:${NC}"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}9. 리소스 제한 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Consumer에 리소스 제한 설정됨" \
    "kubectl get deployment log-consumer -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' | grep -q memory"

check_item "Kafka에 리소스 제한 설정됨" \
    "kubectl get statefulset kafka -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' | grep -q memory"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}10. Health Probe 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Producer API에 Liveness Probe 설정" \
    "kubectl get deployment log-producer-api -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' | grep -q httpGet"

check_item "Aggregator에 Readiness Probe 설정" \
    "kubectl get deployment log-aggregator -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' | grep -q httpGet"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}11. 기능 테스트${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

# 개선 버전 1: 내부 테스트
echo -ne "${YELLOW}Testing Kafka connectivity (internal)...${NC}"
if kubectl exec -n $NAMESPACE statefulset/kafka -- \
    kafka-broker-api-versions --bootstrap-server localhost:9092 2>&1 | grep -q "ApiVersion"; then
    echo -e " ${GREEN}✅ PASS${NC}"
    ((PASS++))
else
    echo -e " ${RED}❌ FAIL${NC}"
    ((FAIL++))
fi

# 개선 버전 3: MongoDB 테스트
echo -ne "${YELLOW}Testing MongoDB connectivity...${NC}"
if kubectl exec -n $NAMESPACE statefulset/mongodb -- \
    mongosh --quiet --eval "db.adminCommand('ping').ok" 2>&1 | grep -q "1"; then
    echo -e " ${GREEN}✅ PASS${NC}"
    ((PASS++))
else
    echo -e " ${RED}❌ FAIL${NC}"
    ((FAIL++))
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}12. 파일 구조 확인${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

check_item "Namespace YAML 존재" \
    "test -f k8s/base/namespace.yaml"

check_item "ConfigMap YAML 존재" \
    "test -f k8s/base/configmap.yaml"

check_item "Secret YAML 존재" \
    "test -f k8s/base/secret.yaml"

check_item "MongoDB StatefulSet YAML 존재" \
    "test -f k8s/base/mongodb/statefulset.yaml"

check_item "Kafka StatefulSet YAML 존재" \
    "test -f k8s/base/kafka/statefulset.yaml"

check_item "Producer Deployment YAML 존재" \
    "test -f k8s/base/producers/deployment.yaml"

check_item "Consumer Deployment YAML 존재" \
    "test -f k8s/base/consumers/deployment.yaml"

check_item "Aggregator Deployment YAML 존재" \
    "test -f k8s/base/aggregator/deployment.yaml"

check_item "Grafana Deployment YAML 존재" \
    "test -f k8s/base/grafana/deployment.yaml"

check_item "HPA YAML 존재" \
    "test -f k8s/base/hpa.yaml"

check_item "배포 스크립트 존재" \
    "test -f scripts/k8s/deploy-k8s.sh"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}최종 결과${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

TOTAL=$((PASS + FAIL))
PERCENTAGE=$((PASS * 100 / TOTAL))

echo ""
echo -e "Total Checks: $TOTAL"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo -e "Success Rate: $PERCENTAGE%"
echo ""

if [ $PERCENTAGE -ge 90 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ TASK-9 COMPLETED SUCCESSFULLY! ($PERCENTAGE%)              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 0
elif [ $PERCENTAGE -ge 70 ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  ⚠️  TASK-9 MOSTLY COMPLETED ($PERCENTAGE%)                    ║${NC}"
    echo -e "${YELLOW}║  Some components need attention                           ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 1
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ TASK-9 INCOMPLETE ($PERCENTAGE%)                           ║${NC}"
    echo -e "${RED}║  Significant issues need to be resolved                   ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    exit 1
fi