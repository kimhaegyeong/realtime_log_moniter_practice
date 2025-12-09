#!/bin/bash

echo "=== Log Consumer Test ==="

# 1. 테스트 로그 생성 (100개)
echo -e "\n1. Generating test logs..."
curl -s -X POST "http://localhost:8000/api/logs/batch?count=100"

echo -e "\n\nWaiting for logs to be processed (5 seconds)..."
sleep 5

# 2. MongoDB에서 로그 확인
echo -e "\n2. Checking MongoDB for logs..."
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "db.logs.countDocuments()"

# 3. 최근 5개 로그 확인
echo -e "\n3. Recent 5 logs from MongoDB:"
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "db.logs.find().sort({timestamp: -1}).limit(5).forEach(printjson)"

# 4. 서비스별 로그 개수
echo -e "\n4. Logs count by service:"
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "db.logs.aggregate([
    {\$group: {_id: '\$service', count: {\$sum: 1}}},
    {\$sort: {count: -1}}
  ]).forEach(printjson)"

# 5. 로그 레벨별 개수
echo -e "\n5. Logs count by level:"
docker exec mongodb mongosh logs --quiet \
  -u admin -p admin123 --authenticationDatabase admin \
  --eval "db.logs.aggregate([
    {\$group: {_id: '\$level', count: {\$sum: 1}}},
    {\$sort: {count: -1}}
  ]).forEach(printjson)"

# 6. Consumer 로그 확인
echo -e "\n6. Consumer logs (last 20 lines):"
docker-compose logs --tail=20 log-consumer

echo -e "\n✅ Consumer test completed!"
