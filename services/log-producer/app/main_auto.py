"""
자동 로그 생성 모드를 지원하는 Producer
"""
import os
import logging
import signal
import sys
import asyncio
from dotenv import load_dotenv
from app.producer import LogProducer
from app.auto_generator import AutoLogGenerator
from app.models.log import ServiceName

# 환경변수 로드
load_dotenv()

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# 환경변수
KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "logs")
SERVICE_NAME = os.getenv("SERVICE_NAME", "api-service")
LOGS_PER_SECOND = int(os.getenv("LOGS_PER_SECOND", "1"))

# 전역 변수
producer = None
auto_generator = None


def signal_handler(signum, frame):
    """시그널 핸들러 (Graceful Shutdown)"""
    logger.info(f"Received signal {signum}, shutting down gracefully...")
    
    if auto_generator:
        auto_generator.stop()
    
    if producer:
        producer.close()
    
    sys.exit(0)


async def main():
    """메인 함수"""
    global producer, auto_generator
    
    logger.info("=" * 50)
    logger.info("Starting Auto Log Producer")
    logger.info("=" * 50)
    logger.info(f"Kafka Servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"Kafka Topic: {KAFKA_TOPIC}")
    logger.info(f"Service Name: {SERVICE_NAME}")
    logger.info(f"Logs Per Second: {LOGS_PER_SECOND}")
    logger.info("=" * 50)
    
    # 시그널 핸들러 등록
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        # 서비스 이름 검증
        try:
            service_enum = ServiceName(SERVICE_NAME)
        except ValueError:
            logger.error(f"Invalid service name: {SERVICE_NAME}")
            logger.error(f"Valid options: {[s.value for s in ServiceName]}")
            sys.exit(1)
        
        # Kafka Producer 생성
        logger.info("Creating Kafka Producer...")
        producer = LogProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            topic=KAFKA_TOPIC
        )
        logger.info("Kafka Producer created successfully")
        
        # 자동 생성기 생성
        auto_generator = AutoLogGenerator(
            producer=producer,
            service=service_enum,
            logs_per_second=LOGS_PER_SECOND
        )
        
        # 자동 로그 생성 시작
        await auto_generator.start()
        
    except KeyboardInterrupt:
        logger.info("Producer interrupted by user")
        
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
        
    finally:
        # 정리
        if auto_generator:
            auto_generator.stop()
        
        if producer:
            producer.close()
        
        logger.info("Auto Log Producer stopped")


if __name__ == "__main__":
    asyncio.run(main())
