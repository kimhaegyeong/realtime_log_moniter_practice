#!/bin/bash

echo "=== Applying Performance Optimizations ==="

# 색상
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${YELLOW}1. Stopping all services...${NC}"
docker-compose down

echo -e "\n${YELLOW}2. Applying MongoDB indexes...${NC}"
docker-compose up -d mongodb
sleep 10
./scripts/optimize-mongodb-indexes.sh

echo -e "\n${YELLOW}3. Starting Kafka and optimizing...${NC}"
docker-compose up -d zookeeper kafka
sleep 15
./scripts/optimize-kafka-partitions.sh

echo -e "\n${YELLOW}4. Starting all services...${NC}"
docker-compose up -d

echo -e "\n${YELLOW}5. Waiting for services to be ready...${NC}"
sleep 30

echo -e "\n${YELLOW}6. Verifying setup...${NC}"
docker-compose ps

echo -e "\n${GREEN}✅ Optimizations applied successfully${NC}"
echo ""
echo "Run performance test with:"
echo "  ./scripts/benchmark-after-optimization.sh"
