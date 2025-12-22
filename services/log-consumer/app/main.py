"""
Log Consumer 메인 애플리케이션
"""

import os
import logging
import signal
import sys
from dotenv import load_dotenv
from app.consumer import LogConsumer
from app.database.mongodb import MongoDBHandler
from prometheus_client import start_http_server

# 환경변수 로드
load_dotenv()

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
logger = logging.getLogger(__name__)

# 환경변수
KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "logs")
KAFKA_GROUP_ID = os.getenv("KAFKA_GROUP_ID", "log-consumer-group")
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://admin:admin123@mongodb:27017/")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "logs")
BATCH_SIZE = int(os.getenv("BATCH_SIZE", "100"))
METRICS_PORT = int(os.getenv("METRICS_PORT", "8080"))

# 전역 변수
consumer = None
mongodb_handler = None


def signal_handler(signum, frame):
    """시그널 핸들러 (Graceful Shutdown)"""
    logger.info(f"Received signal {signum}, shutting down gracefully...")

    if consumer:
        consumer.close()

    if mongodb_handler:
        mongodb_handler.close()

    sys.exit(0)


def main():
    """메인 함수"""
    global consumer, mongodb_handler

    logger.info("=" * 50)
    logger.info("Starting Log Consumer Service")
    logger.info("=" * 50)
    logger.info(f"Kafka Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Kafka Topic: {KAFKA_TOPIC}")
    logger.info(f"Consumer Group: {KAFKA_GROUP_ID}")
    logger.info(f"MongoDB URI: {MONGODB_URI}")
    logger.info(f"MongoDB Database: {MONGODB_DATABASE}")
    logger.info(f"Batch Size: {BATCH_SIZE}")
    logger.info(f"Metrics Port: {METRICS_PORT}")
    logger.info("=" * 50)

    # Start Prometheus Metrics Server
    start_http_server(METRICS_PORT)
    logger.info(f"Prometheus metrics server started on port {METRICS_PORT}")

    # 시그널 핸들러 등록 (Ctrl+C, SIGTERM)
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    try:
        # MongoDB 연결
        logger.info("Connecting to MongoDB...")
        mongodb_handler = MongoDBHandler(
            connection_string=MONGODB_URI, database_name=MONGODB_DATABASE
        )
        logger.info("MongoDB connection established")

        # Kafka Consumer 생성
        logger.info("Creating Kafka Consumer...")
        consumer = LogConsumer(
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            topic=KAFKA_TOPIC,
            group_id=KAFKA_GROUP_ID,
            mongodb_handler=mongodb_handler,
            batch_size=BATCH_SIZE,
        )
        logger.info("Kafka Consumer created successfully")

        # 메시지 소비 시작
        logger.info("Starting message consumption (Press Ctrl+C to stop)...")
        consumer.consume_messages()

    except KeyboardInterrupt:
        logger.info("Consumer interrupted by user")

    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)

    finally:
        # 정리
        if consumer:
            consumer.close()

        if mongodb_handler:
            mongodb_handler.close()

        logger.info("Log Consumer Service stopped")


if __name__ == "__main__":
    main()
