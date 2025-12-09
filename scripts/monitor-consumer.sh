#!/bin/bash

echo "=== Log Consumer Monitoring ==="

while true; do
    clear
    echo "=== Real-time Consumer Monitoring ==="
    echo "Time: $(date)"
    echo ""

    # 1. 총 로그 개수
    echo "📊 Total logs in MongoDB:"
    docker exec mongodb mongosh logs --quiet \
      -u admin -p admin123 --authenticationDatabase admin \
      --eval "print(db.logs.countDocuments())"

    # 2. Consumer 상태
    echo -e "\n🔄 Consumer Status:"
    docker-compose ps log-consumer

    # 3. 최근 로그 (1개)
    echo -e "\n📝 Latest log:"
    docker exec mongodb mongosh logs --quiet \
      -u admin -p admin123 --authenticationDatabase admin \
      --eval "db.logs.find().sort({timestamp: -1}).limit(1).forEach(printjson)"

    echo -e "\n(Press Ctrl+C to stop monitoring)"
    sleep 5
done
