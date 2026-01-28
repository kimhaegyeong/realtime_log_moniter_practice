#!/bin/bash

# 무중단 배포 테스트 스크립트
# 이 스크립트는 Rolling Update가 서비스 중단 없이 진행되는지 확인합니다.

set -e

NAMESPACE="log-monitoring"
SERVICE_NAME="${1:-log-producer-api}"
NEW_IMAGE_TAG="${2:-v2.0.0}"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Rolling Update 무중단 배포 테스트                        ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. 현재 배포 상태 확인
echo -e "${YELLOW}[1/6] 현재 배포 상태 확인${NC}"
CURRENT_IMAGE=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
CURRENT_REPLICAS=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.replicas}')
echo "  서비스: $SERVICE_NAME"
echo "  현재 이미지: $CURRENT_IMAGE"
echo "  현재 Replicas: $CURRENT_REPLICAS"
echo ""

# 2. Health Check 엔드포인트 확인 (HTTP 서비스인 경우)
if [[ "$SERVICE_NAME" == "log-producer-api" ]] || [[ "$SERVICE_NAME" == "log-aggregator" ]]; then
    echo -e "${YELLOW}[2/6] Health Check 엔드포인트 테스트 (클러스터 내부 네트워크)${NC}"
    PORT=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "8000")
    SERVICE_URL="http://${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local:${PORT}/health"
    
    echo "  Service URL: $SERVICE_URL"
    echo "  클러스터 내부 DNS를 통한 접근 테스트..."
    
    HEALTH_CHECK_COUNT=0
    HEALTH_CHECK_SUCCESS=0
    
    # 이전에 남아있을 수 있는 Pod 정리
    kubectl delete pod -n $NAMESPACE -l run=healthcheck-${SERVICE_NAME} --ignore-not-found=true > /dev/null 2>&1
    
    # 임시 Pod를 한 번 생성하여 여러 번 요청
    POD_NAME="healthcheck-${SERVICE_NAME}-$$"
    echo "  임시 Pod 생성 중: $POD_NAME"
    if kubectl run $POD_NAME \
        --restart=Never \
        --image=curlimages/curl:latest \
        --namespace=$NAMESPACE \
        --command -- sh -c "sleep 3600" > /dev/null 2>&1; then
        echo "  Pod 생성 완료. 준비 대기 중..."
        # Pod가 준비될 때까지 대기
        if kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=30s > /dev/null 2>&1; then
            echo "  Pod 준비 완료. Health Check 시작..."
            for i in {1..10}; do
                # Pod 내부에서 curl 실행 (에러 발생해도 계속 진행)
                set +e
                if kubectl exec $POD_NAME -n $NAMESPACE -- curl -sf --max-time 5 ${SERVICE_URL} > /dev/null 2>&1; then
                    HEALTH_CHECK_SUCCESS=$((HEALTH_CHECK_SUCCESS + 1))
                    echo "  [${i}/10] ✅ 성공"
                else
                    echo "  [${i}/10] ❌ 실패"
                fi
                set -e
                HEALTH_CHECK_COUNT=$((HEALTH_CHECK_COUNT + 1))
                sleep 1
            done
        else
            echo -e "  ${RED}⚠️  Pod 준비 대기 시간 초과${NC}"
        fi
        # Pod 삭제
        echo "  임시 Pod 삭제 중..."
        kubectl delete pod $POD_NAME -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1
    else
        echo -e "  ${RED}⚠️  Pod 생성 실패${NC}"
    fi
    
    echo "  Health Check 성공률: $HEALTH_CHECK_SUCCESS/$HEALTH_CHECK_COUNT"
    echo ""
fi

# 3. Pod 상태 확인
echo -e "${YELLOW}[3/6] 배포 전 Pod 상태 확인${NC}"
kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME --no-headers | awk '{print "  " $1 " - " $2 " - " $3}'
echo ""

# 4. Rolling Update 시작
echo -e "${YELLOW}[4/6] Rolling Update 시작${NC}"
echo "  새 이미지 태그: $NEW_IMAGE_TAG"

# 이미지 존재 여부 확인 및 자동 빌드
NEW_IMAGE="$SERVICE_NAME:$NEW_IMAGE_TAG"
IMAGE_EXISTS=false

if command -v minikube &> /dev/null; then
    echo "  이미지 존재 여부 확인 중..."
    if minikube image ls 2>/dev/null | grep -q "$NEW_IMAGE"; then
        IMAGE_EXISTS=true
        echo -e "  ${GREEN}✅ 이미지 '$NEW_IMAGE'가 minikube에 있습니다.${NC}"
    else
        echo -e "  ${YELLOW}⚠️  이미지 '$NEW_IMAGE'가 minikube에 없습니다.${NC}"
        
        # 이미지 빌드 및 로드 시도
        if [ -d "./services/log-producer" ] && [ "$SERVICE_NAME" == "log-producer-api" ]; then
            echo "  이미지 빌드 및 로드 중..."
            # minikube Docker 환경 사용
            eval $(minikube -p minikube docker-env)
            
            if docker build -t $NEW_IMAGE ./services/log-producer 2>&1; then
                echo -e "  ${GREEN}✅ 이미지 빌드 완료: $NEW_IMAGE${NC}"
                IMAGE_EXISTS=true
            else
                echo -e "  ${RED}❌ 이미지 빌드 실패${NC}"
            fi
        elif [ -d "./services/log-aggregator" ] && [ "$SERVICE_NAME" == "log-aggregator" ]; then
            echo "  이미지 빌드 및 로드 중..."
            eval $(minikube -p minikube docker-env)
            
            if docker build -t $NEW_IMAGE ./services/log-aggregator 2>&1; then
                echo -e "  ${GREEN}✅ 이미지 빌드 완료: $NEW_IMAGE${NC}"
                IMAGE_EXISTS=true
            else
                echo -e "  ${RED}❌ 이미지 빌드 실패${NC}"
            fi
        else
            echo -e "  ${YELLOW}⚠️  서비스 디렉토리를 찾을 수 없습니다.${NC}"
        fi
    fi
else
    # minikube가 아닌 경우, 로컬 Docker 이미지 확인
    if docker images | grep -q "$SERVICE_NAME.*$NEW_IMAGE_TAG"; then
        IMAGE_EXISTS=true
        echo -e "  ${GREEN}✅ 이미지 '$NEW_IMAGE'가 로컬에 있습니다.${NC}"
    else
        echo -e "  ${YELLOW}⚠️  이미지 '$NEW_IMAGE'가 로컬에 없습니다.${NC}"
    fi
fi

if [ "$IMAGE_EXISTS" = false ]; then
    echo ""
    echo -e "  ${RED}❌ 이미지 '$NEW_IMAGE'를 사용할 수 없습니다.${NC}"
    echo ""
    echo "해결 방법:"
    echo "  1. 이미지를 빌드:"
    if [ "$SERVICE_NAME" == "log-producer-api" ]; then
        echo "     docker build -t $NEW_IMAGE ./services/log-producer"
    elif [ "$SERVICE_NAME" == "log-aggregator" ]; then
        echo "     docker build -t $NEW_IMAGE ./services/log-aggregator"
    fi
    echo ""
    echo "  2. minikube 환경인 경우 이미지 로드:"
    echo "     minikube image load $NEW_IMAGE"
    echo ""
    echo "  3. 또는 존재하는 이미지 태그 사용:"
    echo "     $0 $SERVICE_NAME latest"
    echo ""
    exit 1
fi
echo ""

kubectl set image deployment/$SERVICE_NAME -n $NAMESPACE \
    $(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].name}')=$NEW_IMAGE

echo "  배포 상태 모니터링 중..."
if ! kubectl rollout status deployment/$SERVICE_NAME -n $NAMESPACE --timeout=300s 2>&1; then
    echo -e "${RED}❌ Rolling Update 실패${NC}"
    echo ""
    echo "실패 원인 확인:"
    echo "  1. Pod 상태 확인:"
    kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME
    echo ""
    echo "  2. 실패한 Pod 상세 정보:"
    FAILED_POD=$(kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME --no-headers | grep -E "ImagePullBackOff|ErrImagePull|CrashLoopBackOff" | head -1 | awk '{print $1}')
    if [ -n "$FAILED_POD" ]; then
        echo "  Pod: $FAILED_POD"
        kubectl describe pod $FAILED_POD -n $NAMESPACE | grep -A 5 "Events:" || true
    fi
    echo ""
    echo "  3. 해결 방법:"
    echo "     - 이미지가 존재하는지 확인: docker images | grep $SERVICE_NAME"
    echo "     - minikube 환경인 경우: minikube image load $NEW_IMAGE"
    echo "     - 또는 이미지를 빌드: docker build -t $NEW_IMAGE ./services/log-producer"
    exit 1
fi
echo ""

# 5. 배포 중 서비스 가용성 모니터링
echo -e "${YELLOW}[5/6] 배포 중 서비스 가용성 모니터링 (클러스터 내부 네트워크)${NC}"
if [[ "$SERVICE_NAME" == "log-producer-api" ]] || [[ "$SERVICE_NAME" == "log-aggregator" ]]; then
    PORT=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "8000")
    SERVICE_URL="http://${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local:${PORT}/health"
    
    AVAILABLE_COUNT=0
    TOTAL_REQUESTS=0
    
    echo "  배포 중 Health Check 모니터링 (30초간)..."
    echo "  Service URL: $SERVICE_URL"
    
    # 이전에 남아있을 수 있는 Pod 정리
    kubectl delete pod -n $NAMESPACE -l run=healthcheck-${SERVICE_NAME}-monitor --ignore-not-found=true > /dev/null 2>&1
    
    # 임시 Pod를 한 번 생성하여 여러 번 요청
    POD_NAME="healthcheck-${SERVICE_NAME}-monitor-$$"
    echo "  임시 Pod 생성 중: $POD_NAME"
    if kubectl run $POD_NAME \
        --restart=Never \
        --image=curlimages/curl:latest \
        --namespace=$NAMESPACE \
        --command -- sh -c "sleep 3600" > /dev/null 2>&1; then
        echo "  Pod 생성 완료. 준비 대기 중..."
        # Pod가 준비될 때까지 대기
        if kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=30s > /dev/null 2>&1; then
            echo "  Pod 준비 완료. 모니터링 시작..."
            for i in {1..30}; do
                # Pod 내부에서 curl 실행 (에러 발생해도 계속 진행)
                set +e
                if kubectl exec $POD_NAME -n $NAMESPACE -- curl -sf --max-time 5 ${SERVICE_URL} > /dev/null 2>&1; then
                    AVAILABLE_COUNT=$((AVAILABLE_COUNT + 1))
                fi
                set -e
                TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
                # 진행 상황 표시 (매 5초마다)
                if [ $((i % 5)) -eq 0 ]; then
                    echo "  진행: ${i}/30 (성공: ${AVAILABLE_COUNT})"
                fi
                sleep 1
            done
        else
            echo -e "  ${RED}⚠️  Pod 준비 대기 시간 초과${NC}"
        fi
        # Pod 삭제
        echo "  임시 Pod 삭제 중..."
        kubectl delete pod $POD_NAME -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1
    else
        echo -e "  ${RED}⚠️  Pod 생성 실패${NC}"
    fi
    
    AVAILABILITY=$(echo "scale=2; $AVAILABLE_COUNT * 100 / $TOTAL_REQUESTS" | bc)
    echo "  서비스 가용성: ${AVAILABILITY}% ($AVAILABLE_COUNT/$TOTAL_REQUESTS)"
    
    if (( $(echo "$AVAILABILITY >= 95" | bc -l) )); then
        echo -e "  ${GREEN}✅ 무중단 배포 성공 (가용성 >= 95%)${NC}"
    else
        echo -e "  ${RED}❌ 무중단 배포 실패 (가용성 < 95%)${NC}"
    fi
    echo ""
fi

# 6. 최종 상태 확인
echo -e "${YELLOW}[6/6] 최종 배포 상태 확인${NC}"
NEW_IMAGE=$(kubectl get deployment $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "  새 이미지: $NEW_IMAGE"
kubectl get pods -n $NAMESPACE -l app=$SERVICE_NAME --no-headers | awk '{print "  " $1 " - " $2 " - " $3}'
echo ""

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Rolling Update 테스트 완료                                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "사용법:"
echo "  $0 [서비스명] [새이미지태그]"
echo ""
echo "예시:"
echo "  $0 log-producer-api v2.0.0"
echo "  $0 log-aggregator v2.0.0"
echo "  $0 log-consumer v2.0.0"
