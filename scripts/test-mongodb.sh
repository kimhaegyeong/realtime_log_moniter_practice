#!/bin/bash

echo "=== MongoDB Health Check ==="

# MongoDB 연결 테스트
docker exec mongodb mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ MongoDB is running"
else
    echo "❌ MongoDB is not running"
    exit 1
fi

# 데이터베이스 확인
echo -e "\n=== Databases ==="
docker exec mongodb mongosh --quiet --eval "db.adminCommand('listDatabases')"

# 컬렉션 확인
echo -e "\n=== Collections in 'logs' database ==="
docker exec mongodb mongosh logs --quiet --eval "db.getCollectionNames()"

# 인덱스 확인
echo -e "\n=== Indexes on 'logs' collection ==="
docker exec mongodb mongosh logs --quiet --eval "db.logs.getIndexes()"

# 샘플 데이터 삽입
echo -e "\n=== Inserting test document ==="
docker exec mongodb mongosh logs --quiet --eval '
  db.logs.insertOne({
    timestamp: new Date(),
    level: "INFO",
    service: "test-service",
    message: "Test log entry",
    metadata: { test: true }
  })
'

# 데이터 확인
echo -e "\n=== Sample documents ==="
docker exec mongodb mongosh logs --quiet --eval "db.logs.find().limit(3)"

echo -e "\n✅ MongoDB test completed!"
