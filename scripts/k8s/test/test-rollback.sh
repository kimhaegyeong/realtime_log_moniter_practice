#!/bin/bash

# Rollback 시나리오 테스트 스크립트
# 이 스크립트는 배포 실패 시나리오를 시뮬레이션하고 롤백을 테스트합니다.

set -e

NAMESPACE="log-monitoring"
SERVICE_NAME="${1:-log-producer-api}"
BAD_IMAGE_TAG="${2:-v-broken}"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Rollback 시나리오 테스트                                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. 현재 배포 상태 및 이전 버전 저장
echo -e "${YELLOW}[1/7] 현재 배포 상태 확인${NC}"
CURRENT_IMAGE=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
# rollout history에서 숫자로 시작하는 라인만 필터링하여 마지막 revision 가져오기
CURRENT_REVISION=$(kubectl rollout history deployment/$SERVICE_NAME -n $NAMESPACE 2>/dev/null | grep -E '^[[:space:]]*[0-9]+' | tail -1 | awk '{print $1}' | tr -d '[:space:]')
echo "  서비스: $SERVICE_NAME"
echo "  현재 이미지: $CURRENT_IMAGE"
echo "  현재 Revision: ${CURRENT_REVISION:-없음}"
echo ""

# 2. 배포 이력 확인
echo -e "${YELLOW}[2/7] 배포 이력 확인${NC}"
kubectl rollout history deployment/$SERVICE_NAME -n $NAMESPACE
echo ""

# 3. 잘못된 이미지로 배포 시도
echo -e "${YELLOW}[3/7] 잘못된 이미지로 배포 시도${NC}"
echo "  잘못된 이미지 태그: $BAD_IMAGE_TAG"
kubectl set image deployment/$SERVICE_NAME -n $NAMESPACE \
    $(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].name}')=$SERVICE_NAME:$BAD_IMAGE_TAG

echo "  배포 상태 모니터링 중 (최대 60초)..."
TIMEOUT=60
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    ROLLOUT_STATUS=$(kubectl rollout status deployment/$SERVICE_NAME -n $NAMESPACE --timeout=5s 2>&1 || true)
    
    if echo "$ROLLOUT_STATUS" | grep -q "successfully rolled out"; then
        echo -e "  ${RED}⚠️  배포가 성공했지만, 이는 예상과 다른 동작입니다.${NC}"
        break
    elif echo "$ROLLOUT_STATUS" | grep -q "error\|failed\|deadline exceeded"; then
        echo -e "  ${YELLOW}⚠️  배포 실패 감지 (예상된 동작)${NC}"
        break
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

# 4. Pod 상태 확인 (실패한 Pod 확인)
echo -e "${YELLOW}[4/7] Pod 상태 확인${NC}"
kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME
echo ""

FAILED_PODS=$(kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME --no-headers | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | wc -l)
if [ "$FAILED_PODS" -gt 0 ]; then
    echo -e "  ${RED}❌ 실패한 Pod 발견: $FAILED_PODS 개${NC}"
    kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME --no-headers | grep -E "Error|CrashLoopBackOff|ImagePullBackOff" | awk '{print "    " $1 " - " $2 " - " $3}'
else
    echo -e "  ${YELLOW}⚠️  실패한 Pod가 없습니다. 수동으로 롤백을 테스트합니다.${NC}"
fi
echo ""

# 5. Rollback 실행
echo -e "${YELLOW}[5/7] Rollback 실행${NC}"

# 롤백 전 현재 이미지 확인 (잘못된 이미지가 배포된 상태)
CURRENT_BAD_IMAGE=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')

# 롤백 실행
ROLLBACK_OUTPUT=""
if [ -n "$CURRENT_REVISION" ] && [ "$CURRENT_REVISION" != "" ]; then
    echo "  이전 Revision으로 롤백: $CURRENT_REVISION"
    ROLLBACK_OUTPUT=$(kubectl rollout undo deployment/$SERVICE_NAME -n $NAMESPACE --to-revision=$CURRENT_REVISION 2>&1)
else
    echo "  이전 Revision으로 자동 롤백 (revision 번호 미지정)"
    ROLLBACK_OUTPUT=$(kubectl rollout undo deployment/$SERVICE_NAME -n $NAMESPACE 2>&1)
fi

# 롤백 결과 확인
if echo "$ROLLBACK_OUTPUT" | grep -q "skipped\|already matches"; then
    echo -e "  ${YELLOW}⚠️  롤백이 스킵되었습니다. 이전 revision으로 강제 롤백 시도...${NC}"
    
    # 현재 revision 목록에서 이전 revision 찾기
    ALL_REVISIONS=$(kubectl rollout history deployment/$SERVICE_NAME -n $NAMESPACE 2>/dev/null | grep -E '^[[:space:]]*[0-9]+' | awk '{print $1}' | sort -n)
    PREV_REVISION=$(echo "$ALL_REVISIONS" | grep -v "^${CURRENT_REVISION}$" | tail -1)
    
    if [ -n "$PREV_REVISION" ] && [ "$PREV_REVISION" != "" ]; then
        echo "  이전 Revision ($PREV_REVISION)으로 롤백 시도..."
        kubectl rollout undo deployment/$SERVICE_NAME -n $NAMESPACE --to-revision=$PREV_REVISION
    else
        # revision이 없으면 이전 이미지로 직접 수정
        echo "  이전 이미지 ($CURRENT_IMAGE)로 직접 수정..."
        CONTAINER_NAME=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].name}')
        kubectl set image deployment/$SERVICE_NAME -n $NAMESPACE $CONTAINER_NAME=$CURRENT_IMAGE
    fi
fi

echo "  롤백 상태 모니터링 중..."
# 롤백이 진행 중인 경우에만 상태 확인
if kubectl rollout status deployment/$SERVICE_NAME -n $NAMESPACE --timeout=10s 2>&1 | grep -q "Waiting\|progressing"; then
    kubectl rollout status deployment/$SERVICE_NAME -n $NAMESPACE --timeout=300s || {
        echo -e "  ${YELLOW}⚠️  롤백 진행 중 오류 발생. Deployment 상태 확인 중...${NC}"
        # 실패한 ReplicaSet 정리 시도
        FAILED_RS=$(kubectl get rs -n $NAMESPACE -l app=$SERVICE_NAME --no-headers | awk '$2+$3+$4==0 || $4==0 {print $1}' | head -1)
        if [ -n "$FAILED_RS" ]; then
            echo "  실패한 ReplicaSet 삭제: $FAILED_RS"
            kubectl delete rs $FAILED_RS -n $NAMESPACE --ignore-not-found=true
        fi
    }
else
    echo -e "  ${GREEN}✅ 롤백이 즉시 완료되었거나 이미 완료된 상태입니다.${NC}"
fi
echo ""

# 6. Rollback 후 상태 확인
echo -e "${YELLOW}[6/7] Rollback 후 상태 확인${NC}"
sleep 2  # 롤백 적용 대기
RESTORED_IMAGE=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "  복원된 이미지: $RESTORED_IMAGE"
echo "  원래 이미지: $CURRENT_IMAGE"

if [ "$RESTORED_IMAGE" == "$CURRENT_IMAGE" ]; then
    echo -e "  ${GREEN}✅ 이미지가 이전 버전으로 복원되었습니다.${NC}"
elif [ "$RESTORED_IMAGE" == "$CURRENT_BAD_IMAGE" ]; then
    echo -e "  ${RED}❌ 이미지가 여전히 잘못된 버전입니다. 수동으로 수정합니다...${NC}"
    CONTAINER_NAME=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].name}')
    kubectl set image deployment/$SERVICE_NAME -n $NAMESPACE $CONTAINER_NAME=$CURRENT_IMAGE
    echo "  이미지 수정 완료. 롤아웃 대기 중..."
    kubectl rollout status deployment/$SERVICE_NAME -n $NAMESPACE --timeout=300s || true
else
    echo -e "  ${YELLOW}⚠️  이미지가 예상과 다릅니다 (복원: $RESTORED_IMAGE, 원래: $CURRENT_IMAGE).${NC}"
fi

kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME
echo ""

# 7. Health Check (HTTP 서비스인 경우)
if [[ "$SERVICE_NAME" == "log-producer-api" ]] || [[ "$SERVICE_NAME" == "log-aggregator" ]]; then
    echo -e "${YELLOW}[7/7] Health Check 테스트 (클러스터 내부 네트워크)${NC}"
    PORT=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "8000")
    SERVICE_URL="http://${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local:${PORT}/health"
    
    echo "  Service URL: $SERVICE_URL"
    echo "  클러스터 내부 DNS를 통한 접근 테스트..."
    
    HEALTH_CHECK_SUCCESS=0
    HEALTH_CHECK_TOTAL=5
    
    # 임시 Pod를 한 번 생성하여 여러 번 요청
    POD_NAME="healthcheck-${SERVICE_NAME}-$$"
    if kubectl run $POD_NAME \
        --restart=Never \
        --image=curlimages/curl:latest \
        --namespace=$NAMESPACE \
        --command -- sh -c "sleep 3600" > /dev/null 2>&1; then
        # Pod가 준비될 때까지 대기
        if kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=30s > /dev/null 2>&1; then
            for i in $(seq 1 $HEALTH_CHECK_TOTAL); do
                # Pod 내부에서 curl 실행
                if kubectl exec $POD_NAME -n $NAMESPACE -- curl -sf --max-time 5 ${SERVICE_URL} > /dev/null 2>&1; then
                    ((HEALTH_CHECK_SUCCESS++))
                    echo "  [${i}/${HEALTH_CHECK_TOTAL}] ✅ 성공"
                else
                    echo "  [${i}/${HEALTH_CHECK_TOTAL}] ❌ 실패"
                fi
                sleep 1
            done
        fi
        # Pod 삭제
        kubectl delete pod $POD_NAME -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1
    fi
    
    if [ $HEALTH_CHECK_SUCCESS -ge 3 ]; then
        echo -e "  ${GREEN}✅ Health Check 성공 ($HEALTH_CHECK_SUCCESS/$HEALTH_CHECK_TOTAL)${NC}"
    else
        echo -e "  ${RED}❌ Health Check 실패 ($HEALTH_CHECK_SUCCESS/$HEALTH_CHECK_TOTAL)${NC}"
        echo -e "  ${YELLOW}⚠️  Service가 클러스터 내부 네트워크에서 접근 가능한지 확인하세요.${NC}"
    fi
    echo ""
fi

# 8. 최종 배포 이력 확인
echo -e "${YELLOW}최종 배포 이력${NC}"
kubectl rollout history deployment/$SERVICE_NAME -n $NAMESPACE
echo ""

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Rollback 테스트 완료                                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "사용법:"
echo "  $0 [서비스명] [잘못된이미지태그]"
echo ""
echo "예시:"
echo "  $0 log-producer-api v-broken"
echo "  $0 log-aggregator v-broken"
echo ""
echo "참고: 실제로 존재하지 않는 이미지 태그를 사용하면 ImagePullBackOff가 발생합니다."
