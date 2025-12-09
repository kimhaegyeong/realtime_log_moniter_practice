#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "=== Real-time Multi-Producer Monitoring ==="
echo "Press Ctrl+C to stop"
echo ""

# 초기 카운트
PREV_COUNT=0

while true; do
    clear
    echo -e "${BLUE}=== Log Monitoring Dashboard ===${NC}"
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 1. MongoDB 총 로그 개수
    CURRENT_COUNT=$(docker exec mongodb mongosh logs --quiet \
      -u admin -p admin123 --authenticationDatabase admin \
      --eval "print(db.logs.countDocuments())" 2>/dev/null)
    
    echo -e "${YELLOW}📊 Total Logs in MongoDB:${NC} $CURRENT_COUNT"
    
    # 증가량 계산
    if [ "$PREV_COUNT" -ne 0 ]; then
        DIFF=$((CURRENT_COUNT - PREV_COUNT))
        RATE=$(echo "scale=1; $DIFF / 5" | bc)
        echo -e "${GREEN}   Rate: ~$RATE logs/sec (last 5 sec)${NC}"
    fi
    PREV_COUNT=$CURRENT_COUNT
    
    # 2. 서비스별 로그 개수
    echo -e "\n${YELLOW}📦 Logs by Service:${NC}"
    docker exec mongodb mongosh logs --quiet \
      -u admin -p admin123 --authenticationDatabase admin \
      --eval "
        db.logs.aggregate([
          {\$group: {_id: '\$service', count: {\$sum: 1}}},
          {\$sort: {count: -1}}
        ]).forEach(function(doc) {
          print('   ' + doc._id + ': ' + doc.count);
        })
      " 2>/dev/null
    
    # 3. 로그 레벨별 개수
    echo -e "\n${YELLOW}🏷️  Logs by Level:${NC}"
    docker exec mongodb mongosh logs --quiet \
      -u admin -p admin123 --authenticationDatabase admin \
      --eval "
        db.logs.aggregate([
          {\$group: {_id: '\$level', count: {\$sum: 1}}},
          {\$sort: {count: -1}}
        ]).forEach(function(doc) {
          print('   ' + doc._id + ': ' + doc.count);
        })
      " 2>/dev/null
    
    # 4. 컨테이너 상태
    echo -e "\n${YELLOW}🐳 Container Status:${NC}"
    docker-compose ps --format "table {{.Name}}\t{{.Status}}" | grep -E "producer|consumer" | sed 's/^/   /'
    
    # 5. 최근 로그 1개
    echo -e "\n${YELLOW}📝 Latest Log:${NC}"
    docker exec mongodb mongosh logs --quiet \
      -u admin -p admin123 --authenticationDatabase admin \
      --eval "
        var log = db.logs.find().sort({timestamp: -1}).limit(1).toArray()[0];
        if (log) {
          print('   Service: ' + log.service + ', Level: ' + log.level);
          print('   Message: ' + log.message);
        }
      " 2>/dev/null
    
    sleep 5
done
