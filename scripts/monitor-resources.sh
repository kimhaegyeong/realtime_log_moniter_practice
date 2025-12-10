#!/bin/bash

echo "=== Real-time Resource Monitoring ==="

LOG_FILE="resource-monitoring.log"
echo "timestamp,container,cpu,memory,network_in,network_out" > $LOG_FILE

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

while true; do
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          Resource Monitoring Dashboard                    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Time: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
    
    # 전체 통계
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | \
      grep -E "NAME|producer|consumer|kafka|mongodb|grafana"
    
    # Kafka lag 확인
    echo ""
    echo -e "${YELLOW}Kafka Consumer Lag:${NC}"
    docker exec kafka kafka-consumer-groups \
      --bootstrap-server localhost:9092 \
      --group log-consumer-group \
      --describe 2>/dev/null | grep -E "TOPIC|logs" | head -12
    
    # MongoDB 통계
    echo ""
    echo -e "${YELLOW}MongoDB Stats:${NC}"
    TOTAL_LOGS=$(docker exec mongodb mongosh logs --quiet \
      -u admin -p admin123 --authenticationDatabase admin \
      --eval "print(db.logs.countDocuments())" 2>/dev/null)
    echo "Total logs: $TOTAL_LOGS"
    
    # 로그에 기록
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.NetIO}}" | \
      grep -E "producer|consumer|kafka|mongodb" | \
      while read line; do
        echo "$TIMESTAMP,$line" >> $LOG_FILE
      done
    
    sleep 5
done
