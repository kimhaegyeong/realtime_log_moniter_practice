#!/bin/bash

echo "=== Stress Test: High Load Scenario ==="

# 각 Producer의 속도를 일시적으로 증가
echo "1. Increasing log generation rate..."

# Producer 설정 변경을 위해 재시작
docker-compose stop producer-api-service producer-auth-service producer-payment-service

# 고부하 설정으로 재시작
docker-compose up -d \
  -e LOGS_PER_SECOND=50 producer-api-service \
  -e LOGS_PER_SECOND=30 producer-auth-service \
  -e LOGS_PER_SECOND=20 producer-payment-service

echo "2. High load mode activated (100 logs/second total)"
echo "   Running for 60 seconds..."

# 초기 카운트
INITIAL=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")

# 60초 대기 (진행 표시)
for i in {60..1}; do
    echo -ne "Time remaining: $i seconds\r"
    sleep 1
done
echo ""

# 최종 카운트
FINAL=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")

NEW_LOGS=$((FINAL - INITIAL))
RATE=$(echo "scale=2; $NEW_LOGS / 60" | bc)

echo ""
echo "=== Stress Test Results ==="
echo "Logs generated: $NEW_LOGS"
echo "Average rate: $RATE logs/second"
echo "Target rate: 100 logs/second"

# 정상 설정으로 복원
echo ""
echo "3. Restoring normal configuration..."
docker-compose restart producer-api-service producer-auth-service producer-payment-service

echo "✅ Stress test completed!"
