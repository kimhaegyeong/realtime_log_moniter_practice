"""
Log Aggregator API 서버
"""
import os
import logging
from contextlib import asynccontextmanager
from typing import Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from app.database.mongodb import MongoDBClient
from app.services.aggregator import LogAggregatorService
from app.models.stats import (
    AggregatedStats,
    ErrorRateResponse,
    TopErrorsResponse,
    TimeSeriesData
)

# 환경변수 로드
load_dotenv()

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 환경변수
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://admin:admin123@mongodb:27017/")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "logs")

# 전역 변수
mongodb_client: MongoDBClient = None
aggregator_service: LogAggregatorService = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """앱 시작/종료 시 실행"""
    global mongodb_client, aggregator_service
    
    # 시작 시
    logger.info("Starting Log Aggregator Service...")
    
    try:
        mongodb_client = MongoDBClient(
            connection_string=MONGODB_URI,
            database_name=MONGODB_DATABASE
        )
        aggregator_service = LogAggregatorService(mongodb_client)
        logger.info("Log Aggregator initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize: {e}")
        aggregator_service = None
    
    yield
    
    # 종료 시
    logger.info("Shutting down Log Aggregator Service...")
    if mongodb_client:
        mongodb_client.close()
    logger.info("Shutdown complete")


# FastAPI 앱 생성
app = FastAPI(
    title="Log Aggregator API",
    description="로그 통계 및 집계 API",
    version="1.0.0",
    lifespan=lifespan
)


@app.get("/")
async def root():
    """루트 엔드포인트"""
    return {
        "service": "log-aggregator",
        "status": "running",
        "mongodb_uri": MONGODB_URI.replace(
            MONGODB_URI.split("@")[0].split("//")[1],
            "***:***"
        ) if "@" in MONGODB_URI else MONGODB_URI
    }


@app.get("/health")
async def health_check():
    """헬스 체크"""
    return {
        "status": "healthy",
        "aggregator_ready": aggregator_service is not None
    }


@app.get("/api/stats/overall", response_model=AggregatedStats)
async def get_overall_stats():
    """
    전체 통계 조회
    
    - 총 로그 개수
    - 서비스별 통계
    - 로그 레벨 분포
    """
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    
    try:
        stats = aggregator_service.get_overall_stats()
        return stats
    except Exception as e:
        logger.error(f"Error getting overall stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/stats/timeseries")
async def get_time_series(
    hours: int = Query(24, ge=1, le=168, description="과거 N시간 (1-168)"),
    service: Optional[str] = Query(None, description="서비스 필터")
):
    """
    시계열 데이터 조회
    
    - 시간대별 로그 개수
    - 선택적으로 특정 서비스 필터링
    """
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    
    try:
        data = aggregator_service.get_time_series(hours=hours, service=service)
        return {
            "hours": hours,
            "service": service or "all",
            "data": data
        }
    except Exception as e:
        logger.error(f"Error getting time series: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/stats/error-rate", response_model=ErrorRateResponse)
async def get_error_rate(
    service: Optional[str] = Query(None, description="서비스 필터"),
    hours: int = Query(24, ge=1, le=168, description="과거 N시간")
):
    """
    에러율 조회
    
    - 전체 또는 특정 서비스의 에러율
    - 지정된 시간 범위 내의 통계
    """
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    
    try:
        error_rate = aggregator_service.get_error_rate(service=service, hours=hours)
        return error_rate
    except Exception as e:
        logger.error(f"Error getting error rate: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/stats/top-errors")
async def get_top_errors(
    limit: int = Query(10, ge=1, le=100, description="조회할 에러 개수")
):
    """
    빈도가 높은 에러 조회
    
    - 가장 자주 발생한 에러 메시지
    - 발생 횟수 및 마지막 발생 시간
    """
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    
    try:
        top_errors = aggregator_service.get_top_errors(limit=limit)
        return {
            "limit": limit,
            "errors": top_errors
        }
    except Exception as e:
        logger.error(f"Error getting top errors: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/stats/service/{service_name}")
async def get_service_stats(service_name: str):
    """
    특정 서비스의 상세 통계
    
    - 서비스별 로그 레벨 분포
    - 시계열 데이터
    - 에러율
    """
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    
    try:
        # 전체 통계에서 해당 서비스 찾기
        overall_stats = aggregator_service.get_overall_stats()
        service_stat = next(
            (s for s in overall_stats.services if s.service == service_name),
            None
        )
        
        if not service_stat:
            raise HTTPException(status_code=404, detail=f"Service '{service_name}' not found")
        
        # 시계열 데이터
        time_series = aggregator_service.get_time_series(hours=24, service=service_name)
        
        # 에러율
        error_rate = aggregator_service.get_error_rate(service=service_name, hours=24)
        
        return {
            "service": service_name,
            "stats": service_stat,
            "time_series_24h": time_series,
            "error_rate_24h": error_rate
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting service stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/aggregate/hourly")
async def trigger_hourly_aggregation():
    """
    시간대별 집계 수동 트리거
    
    (스케줄러로 자동 실행되지만 수동 실행도 가능)
    """
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    
    try:
        aggregator_service.generate_hourly_aggregation()
        return {
            "success": True,
            "message": "Hourly aggregation completed"
        }
    except Exception as e:
        logger.error(f"Error triggering aggregation: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)