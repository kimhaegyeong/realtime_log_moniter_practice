#!/bin/bash

echo "=== MongoDB Index Optimization ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${YELLOW}1. Current indexes:${NC}"
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "db.logs.getIndexes().forEach(function(idx) { printjson(idx); })"

echo -e "\n${YELLOW}2. Creating optimized indexes...${NC}"

# 복합 인덱스 생성
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval '
// 1. 시간 기반 조회 최적화 (내림차순)
db.logs.createIndex(
  { timestamp: -1 },
  { name: "idx_timestamp_desc", background: true }
);

// 2. 서비스별 시간 조회 (가장 자주 사용)
db.logs.createIndex(
  { service: 1, timestamp: -1 },
  { name: "idx_service_time", background: true }
);

// 3. 로그 레벨별 시간 조회
db.logs.createIndex(
  { level: 1, timestamp: -1 },
  { name: "idx_level_time", background: true }
);

// 4. 서비스 + 레벨 복합 (집계 쿼리용)
db.logs.createIndex(
  { service: 1, level: 1 },
  { name: "idx_service_level", background: true }
);

// 5. 에러 조회 최적화
db.logs.createIndex(
  { level: 1, service: 1, timestamp: -1 },
  { name: "idx_errors", 
    partialFilterExpression: { level: { $in: ["ERROR", "CRITICAL"] } },
    background: true }
);

print("✅ Indexes created successfully");
'

echo -e "\n${YELLOW}3. Analyzing index usage...${NC}"
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "db.logs.aggregate([{\$indexStats: {}}]).forEach(printjson)"

echo -e "\n${GREEN}✅ Index optimization completed${NC}"
