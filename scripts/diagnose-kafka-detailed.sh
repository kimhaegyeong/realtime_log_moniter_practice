#!/bin/bash

echo "=== Detailed Kafka Diagnosis ==="

NAMESPACE="log-monitoring"

# 1. Kafka Pod 상태
echo "1. Kafka Pod Status:"
kubectl get pods -n $NAMESPACE -l app=kafka -o wide

# 2. Kafka Pod 로그 (최근 50줄)
echo -e "\n2. Kafka Pod Logs (last 50 lines):"
kubectl logs -n $NAMESPACE statefulset/kafka --tail=50

# 3. Kafka Service 확인
echo -e "\n3. Kafka Service:"
kubectl get svc kafka -n $NAMESPACE -o wide

# 4. Kafka Endpoints 확인
echo -e "\n4. Kafka Endpoints:"
kubectl get endpoints kafka -n $NAMESPACE

# 5. DNS 테스트
echo -e "\n5. DNS Resolution Test:"
kubectl run dnstest --rm -i --restart=Never --image=busybox:1.35 -n $NAMESPACE -- \
  nslookup kafka.log-monitoring.svc.cluster.local

# 6. Kafka Pod에 직접 접속 테스트
echo -e "\n6. Testing Kafka from inside Pod:"
kubectl exec -n $NAMESPACE statefulset/kafka -- \
  kafka-broker-api-versions --bootstrap-server localhost:9092 2>&1 | head -20

# 7. Zookeeper 상태
echo -e "\n7. Zookeeper Status:"
kubectl get pods -n $NAMESPACE -l app=zookeeper

# 8. Zookeeper 연결 테스트
echo -e "\n8. Zookeeper Connection Test:"
kubectl exec -n $NAMESPACE statefulset/zookeeper -- \
  nc -zv localhost 2181

echo -e "\n✅ Diagnosis completed"
