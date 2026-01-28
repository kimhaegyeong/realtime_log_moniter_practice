#!/bin/bash

# AWS EKS 배포 전 필수 조건 확인 스크립트

set -e

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== AWS EKS 배포 전 필수 조건 확인 ===${NC}\n"

ERRORS=0
WARNINGS=0

# === 1. AWS CLI 확인 ===
echo -e "${YELLOW}1. AWS CLI 확인...${NC}"
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI가 설치되지 않았습니다.${NC}"
    echo "  설치: https://aws.amazon.com/cli/"
    ((ERRORS++))
else
    AWS_VERSION=$(aws --version | cut -d' ' -f1 | cut -d'/' -f2)
    echo -e "${GREEN}✓ AWS CLI 설치됨 (버전: ${AWS_VERSION})${NC}"
    
    # AWS 인증 확인
    if aws sts get-caller-identity &> /dev/null; then
        IDENTITY=$(aws sts get-caller-identity)
        if command -v jq &> /dev/null; then
            ACCOUNT_ID=$(echo $IDENTITY | jq -r '.Account')
            USER_ARN=$(echo $IDENTITY | jq -r '.Arn')
        else
            ACCOUNT_ID=$(echo $IDENTITY | grep -oP '"Account":\s*"\K[^"]+')
            USER_ARN=$(echo $IDENTITY | grep -oP '"Arn":\s*"\K[^"]+')
        fi
        echo -e "${GREEN}✓ AWS 인증 성공${NC}"
        echo -e "  Account ID: ${ACCOUNT_ID}"
        echo -e "  User/Role: ${USER_ARN}"
    else
        echo -e "${RED}✗ AWS 인증 실패. 'aws configure'를 실행하세요.${NC}"
        ((ERRORS++))
    fi
fi
echo ""

# === 2. kubectl 확인 ===
echo -e "${YELLOW}2. kubectl 확인...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl이 설치되지 않았습니다.${NC}"
    echo "  설치: https://kubernetes.io/docs/tasks/tools/"
    ((ERRORS++))
else
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3)
    echo -e "${GREEN}✓ kubectl 설치됨 (버전: ${KUBECTL_VERSION})${NC}"
    
    # kubectl 클러스터 연결 확인
    if kubectl cluster-info &> /dev/null; then
        CURRENT_CONTEXT=$(kubectl config current-context)
        echo -e "${GREEN}✓ kubectl이 클러스터에 연결됨${NC}"
        echo -e "  현재 컨텍스트: ${CURRENT_CONTEXT}"
        
        # 노드 확인
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        if [ "$NODE_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✓ 클러스터 노드 수: ${NODE_COUNT}${NC}"
        else
            echo -e "${RED}✗ 클러스터에 노드가 없습니다.${NC}"
            ((ERRORS++))
        fi
    else
        echo -e "${YELLOW}⚠ kubectl이 클러스터에 연결되지 않았습니다.${NC}"
        echo "  EKS 클러스터에 연결하려면:"
        echo "    aws eks update-kubeconfig --region <region> --name <cluster-name>"
        ((WARNINGS++))
    fi
fi
echo ""

# === 3. Docker 확인 ===
echo -e "${YELLOW}3. Docker 확인...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker가 설치되지 않았습니다.${NC}"
    echo "  설치: https://docs.docker.com/get-docker/"
    ((ERRORS++))
else
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    echo -e "${GREEN}✓ Docker 설치됨 (버전: ${DOCKER_VERSION})${NC}"
    
    # Docker 데몬 실행 확인
    if docker info &> /dev/null; then
        echo -e "${GREEN}✓ Docker 데몬 실행 중${NC}"
    else
        echo -e "${RED}✗ Docker 데몬이 실행되지 않았습니다.${NC}"
        ((ERRORS++))
    fi
fi
echo ""

# === 4. EKS 클러스터 확인 ===
echo -e "${YELLOW}4. EKS 클러스터 확인...${NC}"
AWS_REGION=$(aws configure get region 2>/dev/null || echo "ap-northeast-2")

if [ -z "$EKS_CLUSTER_NAME" ]; then
    echo -e "${YELLOW}EKS_CLUSTER_NAME 환경 변수가 설정되지 않았습니다.${NC}"
    echo "  기본값 'log-monitoring-cluster'로 확인합니다."
    EKS_CLUSTER_NAME="log-monitoring-cluster"
fi

CLUSTERS=$(aws eks list-clusters --region ${AWS_REGION} --query 'clusters' --output text 2>/dev/null || echo "")

if [ -z "$CLUSTERS" ]; then
    echo -e "${RED}✗ EKS 클러스터가 없습니다.${NC}"
    echo "  클러스터를 생성하세요:"
    echo "    eksctl create cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} --nodegroup-name standard-workers --node-type t3.medium --nodes 2"
    ((ERRORS++))
elif echo "$CLUSTERS" | grep -q "${EKS_CLUSTER_NAME}"; then
    CLUSTER_STATUS=$(aws eks describe-cluster --name ${EKS_CLUSTER_NAME} --region ${AWS_REGION} --query 'cluster.status' --output text 2>/dev/null)
    if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
        echo -e "${GREEN}✓ EKS 클러스터 '${EKS_CLUSTER_NAME}' 확인됨 (상태: ${CLUSTER_STATUS})${NC}"
    else
        echo -e "${YELLOW}⚠ EKS 클러스터 '${EKS_CLUSTER_NAME}' 상태: ${CLUSTER_STATUS}${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${YELLOW}⚠ EKS 클러스터 '${EKS_CLUSTER_NAME}'를 찾을 수 없습니다.${NC}"
    echo "  사용 가능한 클러스터:"
    echo "$CLUSTERS" | sed 's/^/    - /'
    echo "  또는 EKS_CLUSTER_NAME 환경 변수를 설정하세요:"
    echo "    export EKS_CLUSTER_NAME=<cluster-name>"
    ((WARNINGS++))
fi
echo ""

# === 5. ECR 레지스트리 확인 ===
echo -e "${YELLOW}5. ECR 레지스트리 확인...${NC}"
REPOSITORIES=("log-producer" "log-consumer" "log-aggregator")
MISSING_REPOS=()

for repo in "${REPOSITORIES[@]}"; do
    if aws ecr describe-repositories --repository-names ${repo} --region ${AWS_REGION} &> /dev/null; then
        echo -e "${GREEN}✓ ECR 레지스트리 '${repo}' 확인됨${NC}"
    else
        echo -e "${YELLOW}⚠ ECR 레지스트리 '${repo}'가 없습니다. (배포 스크립트에서 자동 생성됨)${NC}"
        MISSING_REPOS+=($repo)
        ((WARNINGS++))
    fi
done

if [ ${#MISSING_REPOS[@]} -gt 0 ]; then
    echo -e "${YELLOW}  다음 명령어로 수동 생성할 수 있습니다:${NC}"
    for repo in "${MISSING_REPOS[@]}"; do
        echo "    aws ecr create-repository --repository-name ${repo} --region ${AWS_REGION}"
    fi
fi
echo ""

# === 6. MSK 클러스터 확인 (선택사항) ===
echo -e "${YELLOW}6. MSK 클러스터 확인 (선택사항)...${NC}"
MSK_CLUSTERS=$(aws kafka list-clusters --region ${AWS_REGION} --query 'ClusterInfoList[].ClusterName' --output text 2>/dev/null || echo "")

if [ -z "$MSK_CLUSTERS" ]; then
    echo -e "${YELLOW}⚠ MSK 클러스터가 없습니다.${NC}"
    echo "  Kafka StatefulSet을 사용하거나 MSK 클러스터를 생성하세요."
    ((WARNINGS++))
else
    echo -e "${GREEN}✓ MSK 클러스터 확인됨:${NC}"
    echo "$MSK_CLUSTERS" | sed 's/^/    - /'
fi
echo ""

# === 7. DocumentDB 클러스터 확인 (선택사항) ===
echo -e "${YELLOW}7. DocumentDB 클러스터 확인 (선택사항)...${NC}"
DOCDB_CLUSTERS=$(aws docdb describe-db-clusters --region ${AWS_REGION} --query 'DBClusters[].DBClusterIdentifier' --output text 2>/dev/null || echo "")

if [ -z "$DOCDB_CLUSTERS" ]; then
    echo -e "${YELLOW}⚠ DocumentDB 클러스터가 없습니다.${NC}"
    echo "  MongoDB StatefulSet을 사용하거나 DocumentDB 클러스터를 생성하세요."
    ((WARNINGS++))
else
    echo -e "${GREEN}✓ DocumentDB 클러스터 확인됨:${NC}"
    echo "$DOCDB_CLUSTERS" | sed 's/^/    - /'
fi
echo ""

# === 8. Kubernetes 매니페스트 확인 ===
echo -e "${YELLOW}8. Kubernetes 매니페스트 확인...${NC}"
if [ -d "k8s/base" ]; then
    echo -e "${GREEN}✓ k8s/base 디렉토리 확인됨${NC}"
    
    # ConfigMap 확인
    if [ -f "k8s/base/configmap.yaml" ]; then
        echo -e "${GREEN}✓ ConfigMap 파일 확인됨${NC}"
        # MSK 주소 확인
        if grep -q "kafka.log-monitoring.svc.cluster.local" k8s/base/configmap.yaml; then
            echo -e "${YELLOW}⚠ ConfigMap에 로컬 Kafka 주소가 있습니다. MSK 주소로 변경하세요.${NC}"
            ((WARNINGS++))
        fi
    else
        echo -e "${RED}✗ ConfigMap 파일이 없습니다.${NC}"
        ((ERRORS++))
    fi
    
    # Secret 확인
    if [ -f "k8s/base/secret.yaml" ]; then
        echo -e "${GREEN}✓ Secret 파일 확인됨${NC}"
        echo -e "${YELLOW}⚠ Secret에 하드코딩된 비밀번호가 있는지 확인하세요.${NC}"
        echo -e "${YELLOW}  프로덕션에서는 AWS Secrets Manager를 사용하는 것을 권장합니다.${NC}"
        ((WARNINGS++))
    else
        echo -e "${YELLOW}⚠ Secret 파일이 없습니다.${NC}"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗ k8s/base 디렉토리가 없습니다.${NC}"
    ((ERRORS++))
fi
echo ""

# === 결과 요약 ===
echo -e "${BLUE}=== 확인 결과 ===${NC}"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 필수 조건이 충족되었습니다!${NC}"
    echo -e "${GREEN}  배포를 진행할 수 있습니다.${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ 경고: ${WARNINGS}개${NC}"
    echo -e "${GREEN}✓ 필수 조건은 모두 충족되었습니다.${NC}"
    echo -e "${YELLOW}  경고 사항을 확인하고 배포를 진행하세요.${NC}"
    exit 0
else
    echo -e "${RED}✗ 오류: ${ERRORS}개, 경고: ${WARNINGS}개${NC}"
    echo -e "${RED}  위의 오류를 해결한 후 다시 시도하세요.${NC}"
    exit 1
fi
