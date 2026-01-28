#!/bin/bash

# AWS EKS 배포 스크립트
# 전제 조건:
# 1. AWS CLI 설정 완료 (aws configure)
# 2. EKS 클러스터 생성 완료
# 3. kubectl이 EKS 클러스터에 연결됨
# 4. ECR 레지스트리 생성 완료 (자동 생성 가능)
# 5. MSK 클러스터 생성 완료 (또는 Kafka StatefulSet 사용)
# 6. DocumentDB 클러스터 생성 완료 (또는 MongoDB StatefulSet 사용)

set -e  # 에러 발생 시 스크립트 중단

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# === Root Directory 설정 ===
ROOT_DIR="$(cd "$(dirname "$0")/../../" && pwd)"
cd $ROOT_DIR

echo -e "${BLUE}=== AWS EKS 배포 스크립트 ===${NC}\n"

# === 환경 변수 확인 ===
echo -e "${YELLOW}1. 환경 변수 확인...${NC}"

# 필수 환경 변수
if [ -z "$AWS_REGION" ]; then
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        echo -e "${RED}Error: AWS_REGION이 설정되지 않았습니다.${NC}"
        echo "다음 중 하나를 실행하세요:"
        echo "  export AWS_REGION=ap-northeast-2"
        echo "  또는 aws configure set region ap-northeast-2"
        exit 1
    fi
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        echo -e "${RED}Error: AWS 계정 ID를 가져올 수 없습니다. AWS CLI 인증을 확인하세요.${NC}"
        exit 1
    fi
fi

if [ -z "$EKS_CLUSTER_NAME" ]; then
    echo -e "${YELLOW}EKS_CLUSTER_NAME이 설정되지 않았습니다. 기본값 'log-monitoring-cluster'를 사용합니다.${NC}"
    EKS_CLUSTER_NAME="log-monitoring-cluster"
fi

if [ -z "$ECR_REGISTRY" ]; then
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi

echo -e "${GREEN}✓ AWS Region: ${AWS_REGION}${NC}"
echo -e "${GREEN}✓ AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${GREEN}✓ EKS Cluster: ${EKS_CLUSTER_NAME}${NC}"
echo -e "${GREEN}✓ ECR Registry: ${ECR_REGISTRY}${NC}\n"

# === kubectl 연결 확인 ===
echo -e "${YELLOW}2. kubectl 연결 확인...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: kubectl이 클러스터에 연결되지 않았습니다.${NC}"
    echo "다음 명령어로 EKS 클러스터에 연결하세요:"
    echo "  aws eks update-kubeconfig --region ${AWS_REGION} --name ${EKS_CLUSTER_NAME}"
    exit 1
fi

CURRENT_CONTEXT=$(kubectl config current-context)
echo -e "${GREEN}✓ 현재 kubectl 컨텍스트: ${CURRENT_CONTEXT}${NC}\n"

# === ECR 로그인 ===
echo -e "${YELLOW}3. ECR 로그인...${NC}"
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
echo -e "${GREEN}✓ ECR 로그인 완료${NC}\n"

# === ECR 레지스트리 확인 및 생성 ===
echo -e "${YELLOW}4. ECR 레지스트리 확인 및 생성...${NC}"
REPOSITORIES=("log-producer" "log-consumer" "log-aggregator")

for repo in "${REPOSITORIES[@]}"; do
    if ! aws ecr describe-repositories --repository-names ${repo} --region ${AWS_REGION} &> /dev/null; then
        echo -e "${YELLOW}ECR 레지스트리 '${repo}'가 없습니다. 생성 중...${NC}"
        aws ecr create-repository \
            --repository-name ${repo} \
            --region ${AWS_REGION} \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        echo -e "${GREEN}✓ ECR 레지스트리 '${repo}' 생성 완료${NC}"
    else
        echo -e "${GREEN}✓ ECR 레지스트리 '${repo}' 확인됨${NC}"
    fi
done
echo ""

# === Docker 이미지 빌드 및 푸시 ===
echo -e "${YELLOW}5. Docker 이미지 빌드 및 ECR 푸시...${NC}"

SERVICES=("log-producer" "log-consumer" "log-aggregator")
IMAGE_TAG="${IMAGE_TAG:-latest}"
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

for service in "${SERVICES[@]}"; do
    SERVICE_DIR="./services/${service}"
    REPO_NAME="${service}"
    IMAGE_NAME="${ECR_REGISTRY}/${REPO_NAME}:${IMAGE_TAG}"
    IMAGE_NAME_COMMIT="${ECR_REGISTRY}/${REPO_NAME}:${GIT_COMMIT}"
    
    echo -e "${BLUE}빌드 중: ${service}...${NC}"
    
    # Docker 이미지 빌드
    docker build -t ${IMAGE_NAME} -t ${IMAGE_NAME_COMMIT} ${SERVICE_DIR}
    
    # ECR에 푸시
    echo -e "${BLUE}ECR에 푸시 중: ${IMAGE_NAME}...${NC}"
    docker push ${IMAGE_NAME}
    docker push ${IMAGE_NAME_COMMIT}
    
    echo -e "${GREEN}✓ ${service} 이미지 빌드 및 푸시 완료${NC}"
done
echo ""

# === Kubernetes 리소스 배포 ===
echo -e "${YELLOW}6. Kubernetes 리소스 배포...${NC}"

# Namespace 생성
kubectl create namespace log-monitoring --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap 및 Secret은 수동으로 확인 필요
echo -e "${YELLOW}⚠ ConfigMap과 Secret이 AWS 환경(MSK, DocumentDB)에 맞게 수정되었는지 확인하세요.${NC}"
echo -e "${YELLOW}   - k8s/base/configmap.yaml: MSK Bootstrap Servers 주소${NC}"
echo -e "${YELLOW}   - k8s/base/secret.yaml: DocumentDB 연결 정보${NC}"
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "배포가 취소되었습니다."
    exit 1
fi

# 기본 리소스 배포 (Namespace, ConfigMap, Secret)
echo -e "${BLUE}기본 리소스 배포 중...${NC}"
kubectl apply -k k8s/base

# 이미지 태그 업데이트를 위한 임시 디렉토리 생성
TEMP_DIR=$(mktemp -d)
cp -r k8s/base ${TEMP_DIR}/k8s-base

# Deployment 파일에서 이미지 태그 업데이트
echo -e "${BLUE}이미지 태그 업데이트 중...${NC}"
find ${TEMP_DIR}/k8s-base -name "*.yaml" -type f -exec sed -i.bak \
    -e "s|image: log-producer:latest|image: ${ECR_REGISTRY}/log-producer:${IMAGE_TAG}|g" \
    -e "s|image: log-consumer:latest|image: ${ECR_REGISTRY}/log-consumer:${IMAGE_TAG}|g" \
    -e "s|image: log-aggregator:latest|image: ${ECR_REGISTRY}/log-aggregator:${IMAGE_TAG}|g" \
    {} \;

# 업데이트된 리소스 배포
kubectl apply -k ${TEMP_DIR}/k8s-base

# 백업 파일 정리
find ${TEMP_DIR}/k8s-base -name "*.bak" -type f -delete
rm -rf ${TEMP_DIR}

echo -e "${GREEN}✓ Kubernetes 리소스 배포 완료${NC}\n"

# === 배포 상태 확인 ===
echo -e "${YELLOW}7. 배포 상태 확인...${NC}"
echo "Pod 상태 확인 중..."
sleep 10

kubectl get pods -n log-monitoring

echo -e "\n${YELLOW}서비스 상태 확인 중...${NC}"
kubectl get svc -n log-monitoring

echo -e "\n${GREEN}=== 배포 완료 ===${NC}"
echo -e "${BLUE}다음 명령어로 상태를 확인하세요:${NC}"
echo "  kubectl get pods -n log-monitoring -w"
echo "  kubectl logs -f <pod-name> -n log-monitoring"
echo "  kubectl get svc -n log-monitoring"
