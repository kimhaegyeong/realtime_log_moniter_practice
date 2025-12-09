#!/bin/bash

echo "=== Load Test: Multiple Producers ==="

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. 현재 상태 확인
echo -e "\n${YELLOW}1. Checking current system status...${NC}"
docker-compose ps

# 2. MongoDB 초기 로그 개수
echo -e "\n${YELLOW}2. Initial log count in MongoDB:${NC}"
INITIAL_COUNT=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")
echo "Initial logs: $INITIAL_COUNT"

# 3. 부하 테스트 시작
echo -e "\n${YELLOW}3. Starting load test (30 seconds)...${NC}"
echo "Expected rate: ~10 logs/second (5+3+2 from auto producers)"

# API를 통한 추가 부하
echo -e "\n${GREEN}Sending additional logs via API...${NC}"
for i in {1..5}; do
    echo "Batch $i/5..."
    curl -s -X POST "http://localhost:8000/api/logs/batch?count=20" > /dev/null
    sleep 2
done

# 30초 대기
echo -e "\n${GREEN}Waiting 30 seconds for auto producers...${NC}"
for i in {30..1}; do
    echo -ne "Time remaining: $i seconds\r"
    sleep 1
done
echo ""

# 4. 결과 확인
echo -e "\n${YELLOW}4. Final log count in MongoDB:${NC}"
FINAL_COUNT=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")
echo "Final logs: $FINAL_COUNT"

# 5. 통계 계산
NEW_LOGS=$((FINAL_COUNT - INITIAL_COUNT))
RATE=$(echo "scale=2; $NEW_LOGS / 30" | bc)

echo -e "\n${GREEN}=== Test Results ===${NC}"
echo "New logs generated: $NEW_LOGS"
echo "Average rate: $RATE logs/second"
echo "Expected: ~10 logs/second"

# 6. 서비스별 로그 분포
echo -e "\n${YELLOW}5. Logs distribution by service:${NC}"
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "
    db.logs.aggregate([
      {\$group: {_id: '\$service', count: {\$sum: 1}}},
      {\$sort: {count: -1}}
    ]).forEach(function(doc) {
      print(doc._id + ': ' + doc.count);
    })
  "

# 7. 로그 레벨별 분포
echo -e "\n${YELLOW}6. Logs distribution by level:${NC}"
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "
    db.logs.aggregate([
      {\$group: {_id: '\$level', count: {\$sum: 1}}},
      {\$sort: {count: -1}}
    ]).forEach(function(doc) {
      print(doc._id + ': ' + doc.count);
    })
  "

# 8. Consumer 처리 상태
echo -e "\n${YELLOW}7. Consumer status (last 10 lines):${NC}"
docker-compose logs --tail=10 log-consumer

# 9. Producer 로그 확인
echo -e "\n${YELLOW}8. Producer logs (last 5 lines each):${NC}"
echo -e "\n${GREEN}API Service:${NC}"
docker-compose logs --tail=5 producer-api-service

echo -e "\n${GREEN}Auth Service:${NC}"
docker-compose logs --tail=5 producer-auth-service

echo -e "\n${GREEN}Payment Service:${NC}"
docker-compose logs --tail=5 producer-payment-service

echo -e "\n${GREEN}✅ Load test completed!${NC}"
