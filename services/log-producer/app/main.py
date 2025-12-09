"""
FastAPI 서버 - Log Producer API
"""
import os
import logging
import asyncio
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from app.models.log import LogRequest, LogResponse, LogEntry, ServiceName
from app.producer import LogProducer
from app.utils.generator import LogGenerator

# 환경변수 로드
load_dotenv()

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 환경변수
KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:29092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "logs")

# 전역 producer 변수
producer: LogProducer = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """앱 시작/종료 시 실행"""
    global producer
    
    # 시작 시
    logger.info("Starting Log Producer Service...")
    producer = LogProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        topic=KAFKA_TOPIC
    )
    logger.info("Kafka Producer initialized successfully")
    
    yield
    
    # 종료 시
    logger.info("Shutting down Log Producer Service...")
    if producer:
        producer.close()
    logger.info("Kafka Producer closed")


# FastAPI 앱 생성
app = FastAPI(
    title="Log Producer API",
    description="Kafka 기반 로그 수집 시스템의 Producer API",
    version="1.0.0",
    lifespan=lifespan
)


@app.get("/")
async def root():
    """루트 엔드포인트"""
    return {
        "service": "log-producer",
        "status": "running",
        "kafka_servers": KAFKA_BOOTSTRAP_SERVERS,
        "topic": KAFKA_TOPIC
    }


@app.get("/health")
async def health_check():
    """헬스 체크 엔드포인트"""
    return {
        "status": "healthy",
        "producer_ready": producer is not None
    }


@app.post("/api/logs", response_model=LogResponse)
async def create_log(log_request: LogRequest):
    """
    로그 생성 API
    
    단일 로그를 Kafka로 전송합니다.
    """
    if not producer:
        raise HTTPException(status_code=503, detail="Producer not initialized")
    
    try:
        # LogEntry 생성
        log_entry = LogEntry(
            level=log_request.level,
            service=log_request.service,
            message=log_request.message,
            metadata=log_request.metadata or {}
        )
        
        # Kafka로 전송
        success = producer.send_log(log_entry)
        
        if success:
            return LogResponse(
                success=True,
                message="Log sent successfully",
                log_id=log_entry.metadata.get("request_id", "unknown")
            )
        else:
            raise HTTPException(status_code=500, detail="Failed to send log to Kafka")
            
    except Exception as e:
        logger.error(f"Error creating log: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/logs/batch")
async def create_batch_logs(count: int = 10, service: str = None):
    """
    배치 로그 생성 API
    
    여러 개의 랜덤 로그를 생성하여 Kafka로 전송합니다.
    """
    if not producer:
        raise HTTPException(status_code=503, detail="Producer not initialized")
    
    if count <= 0 or count > 1000:
        raise HTTPException(status_code=400, detail="Count must be between 1 and 1000")
    
    try:
        # 서비스 이름 검증
        service_enum = None
        if service:
            try:
                service_enum = ServiceName(service)
            except ValueError:
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid service. Must be one of: {[s.value for s in ServiceName]}"
                )
        
        # 랜덤 로그 생성
        log_entries = LogGenerator.generate_batch(count, service=service_enum)
        
        # Kafka로 전송
        success_count, failure_count = producer.send_batch(log_entries)
        
        return {
            "success": True,
            "message": f"Batch logs sent",
            "total": count,
            "success_count": success_count,
            "failure_count": failure_count
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error creating batch logs: {e}")
        raise HTTPException(status_code=500, detail=str(e))


async def generate_continuous_logs(service: ServiceName, rate: int, duration: int):
    """
    연속적으로 로그 생성 (백그라운드 태스크)
    
    Args:
        service: 서비스 이름
        rate: 초당 로그 생성 개수
        duration: 지속 시간 (초)
    """
    logger.info(f"Starting continuous log generation: {rate} logs/sec for {duration} seconds")
    
    interval = 1.0 / rate  # 로그 간 간격
    end_time = asyncio.get_event_loop().time() + duration
    
    while asyncio.get_event_loop().time() < end_time:
        log_entry = LogGenerator.generate_log(service=service)
        producer.send_log(log_entry)
        await asyncio.sleep(interval)
    
    logger.info("Continuous log generation completed")


@app.post("/api/logs/simulate")
async def simulate_logs(
    background_tasks: BackgroundTasks,
    service: str = "api-service",
    rate: int = 10,
    duration: int = 60
):
    """
    로그 시뮬레이션 API
    
    지정된 속도로 연속적으로 로그를 생성합니다.
    
    Args:
        service: 서비스 이름
        rate: 초당 로그 생성 개수 (1-1000)
        duration: 지속 시간 (초, 1-3600)
    """
    if not producer:
        raise HTTPException(status_code=503, detail="Producer not initialized")
    
    if rate <= 0 or rate > 1000:
        raise HTTPException(status_code=400, detail="Rate must be between 1 and 1000")
    
    if duration <= 0 or duration > 3600:
        raise HTTPException(status_code=400, detail="Duration must be between 1 and 3600 seconds")
    
    try:
        service_enum = ServiceName(service)
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid service. Must be one of: {[s.value for s in ServiceName]}"
        )
    
    # 백그라운드에서 실행
    background_tasks.add_task(generate_continuous_logs, service_enum, rate, duration)
    
    return {
        "success": True,
        "message": "Log simulation started",
        "service": service,
        "rate": f"{rate} logs/second",
        "duration": f"{duration} seconds",
        "total_expected": rate * duration
    }


@app.get("/api/stats")
async def get_stats():
    """
    Producer 통계 정보
    """
    if not producer or not producer.producer:
        return {"error": "Producer not initialized"}
    
    metrics = producer.producer.metrics()
    
    return {
        "kafka_servers": KAFKA_BOOTSTRAP_SERVERS,
        "topic": KAFKA_TOPIC,
        "producer_ready": True,
        "metrics_available": len(metrics) > 0
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)