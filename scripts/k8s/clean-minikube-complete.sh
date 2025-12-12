#!/bin/bash

echo "=== Complete Minikube Cleanup ==="

# 1. Minikube 정지
echo "1. Stopping Minikube..."
minikube stop 2>/dev/null || true

# 2. Minikube 삭제
echo "2. Deleting Minikube..."
minikube delete --all --purge

# 3. Docker 컨테이너 정리
echo "3. Cleaning Docker containers..."
docker rm -f $(docker ps -aq) 2>/dev/null || true

# 4. Minikube 캐시 삭제
echo "4. Removing Minikube cache..."
rm -rf ~/.minikube
rm -rf ~/.kube

echo "✅ Cleanup completed"
