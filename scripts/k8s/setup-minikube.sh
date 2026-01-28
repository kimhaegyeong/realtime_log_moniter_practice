#!/bin/bash

echo "=== Setting up Minikube ==="

# Minikube 시작
minikube start --memory=12288 --cpus=6 --driver=docker

# Metrics Server 설치 (HPA 필수)
minikube addons enable metrics-server
minikube addons enable ingress
minikube addons enable ingress-dns


# Ingress 활성화 (선택사항)
minikube addons enable ingress

echo "✅ Minikube setup completed"
echo ""
echo "Now run: ./deploy-k8s.sh"
