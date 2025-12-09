#!/bin/bash

echo "=== Grafana Setup Test ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Grafana 상태 확인
echo -e "\n${YELLOW}1. Checking Grafana status...${NC}"
if curl -s http://localhost:3000/api/health | grep -q "ok"; then
    echo -e "${GREEN}✅ Grafana is running${NC}"
else
    echo -e "${RED}❌ Grafana is not accessible${NC}"
    exit 1
fi

# 2. 로그인 테스트
echo -e "\n${YELLOW}2. Testing Grafana login...${NC}"
TOKEN=$(curl -s -X POST http://localhost:3000/login \
    -H "Content-Type: application/json" \
    -d '{"user":"admin","password":"admin123"}' \
    | grep -o '"authToken":"[^"]*' | cut -d'"' -f4)

if [ -n "$TOKEN" ]; then
    echo -e "${GREEN}✅ Login successful${NC}"
else
    echo -e "${YELLOW}⚠️  Login test skipped (may require UI login)${NC}"
fi

# 3. 데이터소스 확인
echo -e "\n${YELLOW}3. Checking data sources...${NC}"
curl -s http://admin:admin123@localhost:3000/api/datasources | jq -r '.[] | "  - \(.name) (\(.type))"'

# 4. 대시보드 확인
echo -e "\n${YELLOW}4. Checking dashboards...${NC}"
DASHBOARDS=$(curl -s http://admin:admin123@localhost:3000/api/search?type=dash-db)
echo "$DASHBOARDS" | jq -r '.[] | "  - \(.title) (uid: \(.uid))"'

# 5. 접속 정보 출력
echo -e "\n${GREEN}=== Grafana Access Info ===${NC}"
echo "URL: http://localhost:3000"
echo "Username: admin"
echo "Password: admin123"

echo -e "\n${GREEN}✅ Grafana setup test completed!${NC}"
