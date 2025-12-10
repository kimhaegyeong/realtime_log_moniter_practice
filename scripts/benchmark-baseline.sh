#!/bin/bash

echo "=== Performance Baseline Measurement ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# 초기 로그 개수
echo -e "${YELLOW}1. Recording initial state...${NC}"
INITIAL_COUNT=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")
echo "Initial logs: $INITIAL_COUNT"

# 시작 시간
START_TIME=$(date +%s)

# 10초간 대기
echo -e "\n${YELLOW}2. Collecting data for 10 seconds...${NC}"
sleep 10

# 종료 시간
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 최종 로그 개수
FINAL_COUNT=$(docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "print(db.logs.countDocuments())")

# 계산
NEW_LOGS=$((FINAL_COUNT - INITIAL_COUNT))
LOGS_PER_SECOND=$(echo "scale=2; $NEW_LOGS / $DURATION" | bc)

echo -e "\n${GREEN}=== Baseline Results ===${NC}"
echo "Duration: ${DURATION}s"
echo "New logs: $NEW_LOGS"
echo "Current throughput: ${LOGS_PER_SECOND} logs/second"
echo "Target: 10,000 logs/second"

if (( $(echo "$LOGS_PER_SECOND < 10000" | bc -l) )); then
    IMPROVEMENT_NEEDED=$(echo "scale=0; (10000 / $LOGS_PER_SECOND)" | bc)
    echo -e "${YELLOW}Need ${IMPROVEMENT_NEEDED}x improvement${NC}"
else
    echo -e "${GREEN}✅ Already meeting target!${NC}"
fi

# 리소스 사용량
echo -e "\n${YELLOW}3. Resource Usage:${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | \
  grep -E "producer|consumer|kafka|mongodb"
