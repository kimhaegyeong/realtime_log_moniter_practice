#!/bin/bash

# HPA 부하 테스트 스크립트
# Usage: ./load-test.sh [duration_in_seconds]

set -e

NAMESPACE="log-monitoring"
DURATION=${1:-300}  # 기본 5분
LOG_DIR="./load-test-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  HPA 부하 테스트 시작${NC}"
echo -e "${BLUE}========================================${NC}"

# 로그 디렉토리 생성
mkdir -p "$LOG_DIR"

# 1. 사전 확인
echo -e "\n${YELLOW}[1/6] 사전 환경 확인...${NC}"
echo "  - Namespace: $NAMESPACE"
echo "  - 테스트 시간: ${DURATION}초 ($(($DURATION / 60))분)"

# HPA 확인
if ! kubectl get hpa -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}❌ HPA가 배포되지 않았습니다!${NC}"
    echo "먼저 HPA를 배포해주세요:"
    echo "  kubectl apply -f k8s/base/hpa.yaml"
    exit 1
fi

# Metrics Server 확인
if ! kubectl top nodes &>/dev/null; then
    echo -e "${RED}❌ Metrics Server가 작동하지 않습니다!${NC}"
    echo "Metrics Server를 확인해주세요:"
    echo "  kubectl get deployment metrics-server -n kube-system"
    exit 1
fi

echo -e "${GREEN}✓ 환경 확인 완료${NC}"

# 2. 초기 상태 저장
echo -e "\n${YELLOW}[2/6] 초기 상태 저장...${NC}"

RESULT_FILE="$LOG_DIR/test_${TIMESTAMP}.txt"

{
    echo "=========================================="
    echo "HPA 부하 테스트 결과"
    echo "=========================================="
    echo "시작 시간: $(date)"
    echo "테스트 시간: ${DURATION}초"
    echo ""
    echo "========== 초기 상태 =========="
    echo ""
    echo "=== HPA 상태 ==="
    kubectl get hpa -n "$NAMESPACE"
    echo ""
    echo "=== Pod 상태 ==="
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""
    echo "=== 리소스 사용량 ==="
    kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Metrics not ready yet"
    echo ""
} > "$RESULT_FILE"

ORIGINAL_PRODUCER_REPLICAS=$(kubectl get deployment producer-api-service -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
ORIGINAL_CONSUMER_REPLICAS=$(kubectl get deployment log-consumer -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

echo "  초기 Producer Pods: $ORIGINAL_PRODUCER_REPLICAS"
echo "  초기 Consumer Pods: $ORIGINAL_CONSUMER_REPLICAS"
echo -e "${GREEN}✓ 초기 상태 저장 완료${NC}"

# 3. Grafana 안내
echo -e "\n${YELLOW}[3/6] Grafana 모니터링 준비...${NC}"
echo -e "${CYAN}📊 Grafana에서 실시간으로 모니터링하세요!${NC}"
echo ""
echo "  1. 새 터미널에서 Grafana 포트포워딩:"
echo -e "     ${GREEN}kubectl port-forward -n $NAMESPACE svc/grafana 3000:3000${NC}"
echo ""
echo "  2. 브라우저에서 접속:"
echo -e "     ${GREEN}http://localhost:3000${NC}"
echo ""
echo "  3. 모니터링할 메트릭:"
echo "     - Consumer Pod 수 변화"
echo "     - CPU/Memory 사용률"
echo "     - Kafka 메시지 처리량"
echo ""
echo -e "${CYAN}Grafana 준비가 되면 Enter를 눌러 부하 테스트를 시작하세요...${NC}"
read -r

# 4. 부하 생성 시작
echo -e "\n${YELLOW}[4/6] 부하 생성 시작...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Producer를 대폭 증가시켜 부하 생성
TARGET_PRODUCERS=15
echo "📈 Producer를 $ORIGINAL_PRODUCER_REPLICAS → $TARGET_PRODUCERS 개로 증가..."
kubectl scale deployment producer-api-service -n "$NAMESPACE" --replicas=$TARGET_PRODUCERS

echo ""
echo "⏱️  부하 테스트 진행 중... ($DURATION초)"
echo "   Grafana에서 다음을 확인하세요:"
echo "   - Consumer Pod가 자동으로 증가하는지"
echo "   - CPU 사용률이 임계값(70%)을 넘는지"
echo "   - HPA가 정상 작동하는지"
echo ""

# 진행률 표시
START_TIME=$(date +%s)
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    REMAINING=$((DURATION - ELAPSED))
    
    if [ $REMAINING -le 0 ]; then
        break
    fi
    
    PROGRESS=$((ELAPSED * 100 / DURATION))
    BAR_LENGTH=$((PROGRESS / 2))
    BAR=$(printf "%-50s" "$(printf '#%.0s' $(seq 1 $BAR_LENGTH))")
    
    # 현재 상태 표시
    CURRENT_CONSUMERS=$(kubectl get pods -n "$NAMESPACE" -l app=log-consumer --no-headers 2>/dev/null | wc -l)
    
    printf "\r  [%s] %d%% | Consumer Pods: %d | 남은 시간: %ds    " \
           "$BAR" "$PROGRESS" "$CURRENT_CONSUMERS" "$REMAINING"
    
    sleep 5
done

echo ""
echo -e "\n${GREEN}✓ 부하 생성 완료${NC}"

# 5. Scale Down 관찰
echo -e "\n${YELLOW}[5/6] Scale Down 관찰 중...${NC}"

# Producer 원래대로 복구
echo "📉 Producer를 원래대로 복구 ($TARGET_PRODUCERS → $ORIGINAL_PRODUCER_REPLICAS)..."
kubectl scale deployment producer-api-service -n "$NAMESPACE" --replicas=$ORIGINAL_PRODUCER_REPLICAS

echo ""
echo "⏱️  Scale Down 관찰 중... (120초)"
echo "   Grafana에서 다음을 확인하세요:"
echo "   - Consumer Pod가 점진적으로 감소하는지"
echo "   - CPU 사용률이 정상으로 돌아오는지"
echo ""

# Scale Down 관찰
for i in {1..24}; do
    CURRENT_CONSUMERS=$(kubectl get pods -n "$NAMESPACE" -l app=log-consumer --no-headers 2>/dev/null | wc -l)
    PROGRESS=$((i * 100 / 24))
    BAR_LENGTH=$((PROGRESS / 2))
    BAR=$(printf "%-50s" "$(printf '#%.0s' $(seq 1 $BAR_LENGTH))")
    
    printf "\r  [%s] %d%% | Consumer Pods: %d    " "$BAR" "$PROGRESS" "$CURRENT_CONSUMERS"
    sleep 5
done

echo ""
echo -e "\n${GREEN}✓ Scale Down 관찰 완료${NC}"

# 6. 최종 결과 저장
echo -e "\n${YELLOW}[6/6] 최종 결과 수집...${NC}"

{
    echo ""
    echo "========== 최종 상태 =========="
    echo ""
    echo "=== HPA 상태 ==="
    kubectl get hpa -n "$NAMESPACE"
    echo ""
    echo "=== Pod 상태 ==="
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""
    echo "=== 리소스 사용량 ==="
    kubectl top pods -n "$NAMESPACE" 2>/dev/null || echo "Metrics collection completed"
    echo ""
    echo "=== HPA 이벤트 ==="
    kubectl describe hpa -n "$NAMESPACE" | grep -A 20 "Events:"
    echo ""
    echo "=========================================="
    echo "종료 시간: $(date)"
    echo "=========================================="
} >> "$RESULT_FILE"

FINAL_CONSUMER_REPLICAS=$(kubectl get deployment log-consumer -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

# 결과 요약 출력
echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  부하 테스트 완료! ✨${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "\n${BLUE}📊 테스트 결과 요약${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Producer Pods:"
echo "    초기: $ORIGINAL_PRODUCER_REPLICAS → 최대: $TARGET_PRODUCERS → 최종: $ORIGINAL_PRODUCER_REPLICAS"
echo ""
echo "  Consumer Pods:"
echo "    초기: $ORIGINAL_CONSUMER_REPLICAS → 최종: $FINAL_CONSUMER_REPLICAS"
echo ""

# HPA 이벤트 카운트
SCALE_EVENTS=$(kubectl describe hpa -n "$NAMESPACE" | grep "SuccessfulRescale" | wc -l)
echo "  HPA Scaling 이벤트: ${SCALE_EVENTS}회"
echo ""

# HPA 상태 표시
echo "  현재 HPA 상태:"
kubectl get hpa -n "$NAMESPACE" | tail -n +2 | while read line; do
    echo "    $line"
done
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ 결과 저장: ${RESULT_FILE}${NC}"
echo ""

# 추가 분석 방법 안내
echo -e "${CYAN}📋 추가 분석 방법:${NC}"
echo ""
echo "  1. 상세 결과 확인:"
echo -e "     ${YELLOW}cat $RESULT_FILE${NC}"
echo ""
echo "  2. HPA 이벤트 상세 확인:"
echo -e "     ${YELLOW}kubectl describe hpa -n $NAMESPACE${NC}"
echo ""
echo "  3. Consumer Pod 로그 확인:"
echo -e "     ${YELLOW}kubectl logs -l app=log-consumer -n $NAMESPACE --tail=50${NC}"
echo ""
echo "  4. Grafana에서 시각화된 데이터 확인"
echo -e "     ${YELLOW}http://localhost:3000${NC}"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}🎉 테스트 완료!${NC}"
echo -e "${BLUE}========================================${NC}"