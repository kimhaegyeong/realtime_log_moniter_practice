#!/bin/bash

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

while true; do
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Log Monitoring System Dashboard                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}📊 Overall Statistics${NC}"

    # 전체 통계 가져오기
    STATS=$(curl -s http://localhost:8001/api/stats/overall)

    TOTAL=$(echo $STATS | jq -r '.total_logs')
    echo -e "   Total Logs: ${GREEN}$TOTAL${NC}"

    # 서비스별 통계
    echo -e "\n${YELLOW}📦 Logs by Service${NC}"
    echo $STATS | jq -r '.services[] | "   \(.service): \(.total_logs) logs (Error rate: \(.error_rate)%)"'

    # 로그 레벨 분포
    echo -e "\n${YELLOW}🏷️  Log Level Distribution${NC}"
    echo $STATS | jq -r '.log_level_distribution[] | "   \(.level): \(.count) (\(.percentage)%)"'

    # 에러율
    echo -e "\n${YELLOW}⚠️  Error Rates (Last 24h)${NC}"

    for service in api-service auth-service payment-service; do
        ERROR_RATE=$(curl -s "http://localhost:8001/api/stats/error-rate?service=$service&hours=24")
        RATE=$(echo $ERROR_RATE | jq -r '.error_rate')
        ERRORS=$(echo $ERROR_RATE | jq -r '.error_logs')
        echo -e "   $service: ${RED}$RATE%${NC} ($ERRORS errors)"
    done

    # Top 3 에러
    echo -e "\n${YELLOW}🔥 Top 3 Errors${NC}"
    curl -s "http://localhost:8001/api/stats/top-errors?limit=3" | \
        jq -r '.errors[] | "   [\(.service)] \(.message) - \(.count)x"'

    # 컨테이너 상태
    echo -e "\n${YELLOW}🐳 Container Status${NC}"
    docker-compose ps --format "table {{.Name}}\t{{.Status}}" | \
        grep -E "producer|consumer|aggregator" | sed 's/^/   /'

    echo ""
    echo -e "${BLUE}Updated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "Press Ctrl+C to exit"

    sleep 5
done
