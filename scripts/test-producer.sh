#!/bin/bash

echo "=== Log Producer Test ==="

BASE_URL="http://localhost:8000"

# 1. Health check
echo -e "\n1. Health Check"
curl -s $BASE_URL/health | jq

# 2. 단일 로그 전송
echo -e "\n2. Sending single log"
curl -s -X POST $BASE_URL/api/logs \
  -H "Content-Type: application/json" \
  -d '{
    "level": "INFO",
    "service": "api-service",
    "message": "Test log from script",
    "metadata": {"source": "test-script"}
  }' | jq

# 3. 배치 로그 (API Service 10개)
echo -e "\n3. Sending batch logs (api-service)"
curl -s -X POST "$BASE_URL/api/logs/batch?count=10&service=api-service" | jq

# 4. 배치 로그 (Auth Service 5개)
echo -e "\n4. Sending batch logs (auth-service)"
curl -s -X POST "$BASE_URL/api/logs/batch?count=5&service=auth-service" | jq

# 5. 배치 로그 (Payment Service 5개)
echo -e "\n5. Sending batch logs (payment-service)"
curl -s -X POST "$BASE_URL/api/logs/batch?count=5&service=payment-service" | jq

# 6. Kafka에서 메시지 확인
echo -e "\n6. Checking Kafka messages"
docker exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic logs \
  --from-beginning \
  --max-messages 5 \
  --timeout-ms 5000

echo -e "\n✅ Producer test completed!"
