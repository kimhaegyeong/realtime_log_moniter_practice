#!/bin/bash

# HPA 설정 검증 스크립트

set -e

NAMESPACE="log-monitoring"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  HPA 설정 검증${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. Namespace 확인
echo -e "\n${YELLOW}[1/6] Namespace 확인...${NC}"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${GREEN}✓ Namespace '$NAMESPACE' 존재${NC}"
else
    echo -e "${RED}✗ Namespace '$NAMESPACE' 없음${NC}"
    exit 1
fi

# 2. Metrics Server 확인
echo -e "\n${YELLOW}[2/6] Metrics Server 확인...${NC}"
if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
    METRICS_READY=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}')
    if [ "$METRICS_READY" -gt 0 ]; then
        echo -e "${GREEN}✓ Metrics Server 정상 작동 중${NC}"
        
        # Metrics API 테스트
        if kubectl top nodes &>/dev/null; then
            echo -e "${GREEN}✓ Metrics API 응답 정상${NC}"
        else
            echo -e "${RED}✗ Metrics API 응답 없음 (잠시 후 다시 시도)${NC}"
        fi
    else
        echo -e "${RED}✗ Metrics Server가 준비되지 않음${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Metrics Server가 설치되지 않음${NC}"
    echo "다음 명령으로 설치:"
    echo "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    exit 1
fi

# 3. Deployment 리소스 제한 확인
echo -e "\n${YELLOW}[3/6] Deployment 리소스 설정 확인...${NC}"

check_resources() {
    local deployment=$1
    local has_resources=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources}')
    
    if [ -n "$has_resources" ] && [ "$has_resources" != "{}" ]; then
        echo -e "${GREEN}✓ $deployment: 리소스 제한 설정됨${NC}"
        
        # CPU 요청/제한 확인
        CPU_REQUEST=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "none")
        CPU_LIMIT=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "none")
        
        echo "    CPU: request=$CPU_REQUEST, limit=$CPU_LIMIT"
        
        if [ "$CPU_REQUEST" == "none" ]; then
            echo -e "    ${RED}⚠ CPU request가 설정되지 않음 (HPA에 필요)${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ $deployment: 리소스 제한 없음 (HPA 작동 불가)${NC}"
        return 1
    fi
    return 0
}

RESOURCES_OK=true
check_resources "log-consumer" || RESOURCES_OK=false
check_resources "producer-api-service" || RESOURCES_OK=false

if [ "$RESOURCES_OK" = false ]; then
    echo -e "\n${RED}⚠ 리소스 제한이 설정되지 않은 Deployment가 있습니다.${NC}"
    echo "HPA가 정상 작동하려면 CPU/Memory requests가 필요합니다."
    echo ""
    echo "예시 설정:"
    echo "  resources:"
    echo "    requests:"
    echo "      cpu: 100m"
    echo "      memory: 128Mi"
    echo "    limits:"
    echo "      cpu: 500m"
    echo "      memory: 512Mi"
fi

# 4. HPA 리소스 확인
echo -e "\n${YELLOW}[4/6] HPA 리소스 확인...${NC}"

if kubectl get hpa -n "$NAMESPACE" &>/dev/null; then
    HPA_COUNT=$(kubectl get hpa -n "$NAMESPACE" --no-headers | wc -l)
    echo -e "${GREEN}✓ HPA 리소스 존재 (${HPA_COUNT}개)${NC}"
    echo ""
    kubectl get hpa -n "$NAMESPACE"
    
    # 각 HPA 상세 확인
    echo ""
    kubectl get hpa -n "$NAMESPACE" --no-headers | awk '{print $1}' | while read hpa_name; do
        echo -e "\n  ${BLUE}=== HPA: $hpa_name ===${NC}"
        
        TARGET_REF=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.scaleTargetRef.name}')
        MIN_REPLICAS=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')
        MAX_REPLICAS=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}')
        
        echo "    대상: $TARGET_REF"
        echo "    최소/최대: $MIN_REPLICAS / $MAX_REPLICAS"
        
        # 메트릭 확인
        METRICS=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.spec.metrics[*].type}')
        echo "    메트릭: $METRICS"
        
        # 현재 상태
        CURRENT_REPLICAS=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.status.currentReplicas}')
        DESIRED_REPLICAS=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.status.desiredReplicas}')
        
        echo "    현재/목표 Replicas: $CURRENT_REPLICAS / $DESIRED_REPLICAS"
    done
else
    echo -e "${RED}✗ HPA 리소스 없음${NC}"
    echo "다음 명령으로 배포:"
    echo "  kubectl apply -f k8s/base/hpa.yaml"
    exit 1
fi

# 5. 현재 메트릭 확인
echo -e "\n${YELLOW}[5/6] 현재 메트릭 확인...${NC}"

if kubectl top pods -n "$NAMESPACE" &>/dev/null; then
    echo -e "${GREEN}✓ Pod 메트릭 수집 가능${NC}"
    echo ""
    kubectl top pods -n "$NAMESPACE" -l app=log-consumer
    kubectl top pods -n "$NAMESPACE" -l app=producer-api-service
else
    echo -e "${YELLOW}⚠ 메트릭을 아직 수집하지 못함 (시작한지 얼마 안됨)${NC}"
    echo "잠시 후 다시 확인하세요."
fi

# 6. HPA 준비 상태 확인
echo -e "\n${YELLOW}[6/6] HPA 준비 상태 최종 확인...${NC}"

ALL_READY=true

kubectl get hpa -n "$NAMESPACE" --no-headers | awk '{print $1}' | while read hpa_name; do
    CONDITIONS=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}')
    
    if [ "$CONDITIONS" == "True" ]; then
        echo -e "${GREEN}✓ $hpa_name: Scaling Active${NC}"
    elif [ "$CONDITIONS" == "False" ]; then
        echo -e "${RED}✗ $hpa_name: Scaling Inactive${NC}"
        REASON=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].reason}')
        MESSAGE=$(kubectl get hpa "$hpa_name" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].message}')
        echo "  Reason: $REASON"
        echo "  Message: $MESSAGE"
        ALL_READY=false
    else
        echo -e "${YELLOW}⚠ $hpa_name: 상태 확인 불가 (초기화 중일 수 있음)${NC}"
    fi
done

# 최종 결과
echo -e "\n${BLUE}========================================${NC}"
if [ "$ALL_READY" = true ] && [ "$RESOURCES_OK" = true ]; then
    echo -e "${GREEN}✅ HPA 설정이 모두 정상입니다!${NC}"
    echo ""
    echo "다음 단계:"
    echo "  1. Grafana 접속하여 대시보드 확인"
    echo "     kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000"
    echo ""
    echo "  2. 부하 테스트 실행"
    echo "     ./scripts/k8s/load-test.sh 300"
else
    echo -e "${YELLOW}⚠ 일부 설정에 문제가 있습니다.${NC}"
    echo "위의 경고/오류 메시지를 확인하세요."
fi
echo -e "${BLUE}========================================${NC}"