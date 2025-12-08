#!/bin/bash

echo "=== Kafka Health Check ==="

# Kafka 연결 테스트
docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Kafka is running"
else
    echo "❌ Kafka is not running"
    exit 1
fi

# 토픽 생성
echo "Creating topic 'logs'..."
docker exec kafka kafka-topics --create \
  --topic logs \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 1 \
  --if-not-exists

# 토픽 확인
echo -e "\n=== Topic List ==="
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# 샘플 메시지 전송
echo -e "\n=== Sending test message ==="
echo '{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","level":"INFO","service":"test-service","message":"Test message"}' | \
  docker exec -i kafka kafka-console-producer \
    --topic logs \
    --bootstrap-server localhost:9092

echo "✅ Test message sent to Kafka"

# 메시지 확인
echo -e "\n=== Reading messages ==="
docker exec kafka kafka-console-consumer \
  --topic logs \
  --bootstrap-server localhost:9092 \
  --from-beginning \
  --max-messages 5 \
  --timeout-ms 5000

echo -e "\n✅ Kafka test completed!"
