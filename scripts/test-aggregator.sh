#!/bin/bash

echo "=== Log Aggregator Test ==="

BASE_URL="http://localhost:8001"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. Health check
echo -e "\n${YELLOW}1. Health Check${NC}"
curl -s $BASE_URL/health | jq

# 2. 전체 통계
echo -e "\n${YELLOW}2. Overall Statistics${NC}"
curl -s $BASE_URL/api/stats/overall | jq

# 3. 시계열 데이터 (최근 24시간)
echo -e "\n${YELLOW}3. Time Series Data (Last 24 hours)${NC}"
curl -s "$BASE_URL/api/stats/timeseries?hours=24" | jq

# 4. api-service 시계열 데이터
echo -e "\n${YELLOW}4. API Service Time Series${NC}"
curl -s "$BASE_URL/api/stats/timeseries?hours=24&service=api-service" | jq

# 5. 에러율 조회
echo -e "\n${YELLOW}5. Error Rate (All Services)${NC}"
curl -s "$BASE_URL/api/stats/error-rate?hours=24" | jq

# 6. api-service 에러율
echo -e "\n${YELLOW}6. API Service Error Rate${NC}"
curl -s "$BASE_URL/api/stats/error-rate?service=api-service&hours=24" | jq

# 7. Top 5 에러
echo -e "\n${YELLOW}7. Top 5 Errors${NC}"
curl -s "$BASE_URL/api/stats/top-errors?limit=5" | jq

# 8. 특정 서비스 상세 통계
echo -e "\n${YELLOW}8. Service Details (api-service)${NC}"
curl -s "$BASE_URL/api/stats/service/api-service" | jq

echo -e "\n${GREEN}✅ Aggregator test completed!${NC}"
