#!/bin/bash

echo "=== Kafka Partition Optimization ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. 현재 토픽 정보
echo -e "${YELLOW}1. Current topic configuration:${NC}"
docker exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --describe \
  --topic logs

# 2. 파티션 수 증가 (3 → 10)
echo -e "\n${YELLOW}2. Increasing partitions to 10...${NC}"
docker exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --alter \
  --topic logs \
  --partitions 10

# 3. 토픽 설정 최적화
echo -e "\n${YELLOW}3. Optimizing topic configuration...${NC}"
docker exec kafka kafka-configs \
  --bootstrap-server localhost:9092 \
  --entity-type topics \
  --entity-name logs \
  --alter \
  --add-config compression.type=lz4,retention.ms=604800000,segment.ms=3600000

# 4. 확인
echo -e "\n${YELLOW}4. Updated configuration:${NC}"
docker exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --describe \
  --topic logs

docker exec kafka kafka-configs \
  --bootstrap-server localhost:9092 \
  --entity-type topics \
  --entity-name logs \
  --describe

echo -e "\n${GREEN}✅ Kafka optimization completed${NC}"
echo -e "${YELLOW}Note: Restart consumers to pick up new partitions${NC}"
