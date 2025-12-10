#!/bin/bash

echo "=== Performance Benchmark (After Optimization) ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Warming up system (30 seconds)...${NC}"
sleep 30

# 초기 상태
INITIAL_COUNT=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")
echo "Initial logs: $INITIAL_COUNT"

echo -e "\n${YELLOW}Collecting performance data (60 seconds)...${NC}"
START_TIME=$(date +%s)

# 60초간 모니터링
for i in {60..1}; do
    echo -ne "Time remaining: ${i}s\r"
    sleep 1
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 최종 상태
FINAL_COUNT=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")

# 계산
NEW_LOGS=$((FINAL_COUNT - INITIAL_COUNT))
LOGS_PER_SECOND=$(echo "scale=2; $NEW_LOGS / $DURATION" | bc)

echo -e "\n\n${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Performance Test Results                      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Duration: ${DURATION}s"
echo "Logs processed: $NEW_LOGS"
echo "Throughput: ${LOGS_PER_SECOND} logs/second"
echo ""

# 목표 달성 여부
TARGET=10000
PERCENTAGE=$(echo "scale=1; ($LOGS_PER_SECOND / $TARGET) * 100" | bc)

if (( $(echo "$LOGS_PER_SECOND >= $TARGET" | bc -l) )); then
    echo -e "${GREEN}✅ SUCCESS: Target achieved (${PERCENTAGE}% of 10,000 logs/sec)${NC}"
elif (( $(echo "$LOGS_PER_SECOND >= $TARGET * 0.5" | bc -l) )); then
    echo -e "${YELLOW}⚠️  PARTIAL: ${PERCENTAGE}% of target achieved${NC}"
else
    echo -e "${RED}❌ FAIL: Only ${PERCENTAGE}% of target achieved${NC}"
fi

# 상세 통계
echo ""
echo -e "${YELLOW}=== Detailed Statistics ===${NC}"

# Consumer Lag
echo ""
echo "Kafka Consumer Lag:"
docker exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group log-consumer-group \
  --describe 2>/dev/null | grep -E "TOPIC|logs" | head -12

# 서비스별 분포
echo ""
echo "Logs by Service:"
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

# 리소스 사용량
echo ""
echo "Resource Usage:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | \
  grep -E "NAME|producer|consumer|kafka|mongodb"

echo ""
echo -e "${GREEN}✅ Benchmark completed${NC}"
