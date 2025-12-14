"""
Log Aggregator API 서버
"""
import os
import logging
from contextlib import asynccontextmanager
from typing import Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse, PlainTextResponse
from dotenv import load_dotenv
import asyncio
from prometheus_client import Counter, Gauge, Histogram, generate_latest

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

# 로깅 설
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 환경변수
MONGODB_URI = os.getenv("MONGODB_URI", "mongodb://admin:admin123@mongodb:27017/")
MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "logs")



# -------------------------------------------------------------------
# Prometheus Metrics
# -------------------------------------------------------------------
logs_total = Counter(
"logs_total",
"Total number of logs",
["service", "level"]
)


error_rate = Gauge(
"error_rate",
"Error rate by service",
["service"]
)


logs_per_minute = Gauge(
"logs_per_minute",
"Logs processed per minute",
["service"]
)


log_processing_duration = Histogram(
"log_processing_seconds",
"Time spent processing logs"
)

# 전역 변수
mongodb_client: MongoDBClient = None
aggregator_service: LogAggregatorService = None
metrics_task: asyncio.Task | None = None



# -------------------------------------------------------------------
# Metrics Updater
# -------------------------------------------------------------------
last_counts = {}

async def update_prometheus_metrics():
    """Periodically update Prometheus metrics from aggregator service"""
    while True:
        try:
            if aggregator_service:
                stats = aggregator_service.get_overall_stats()
                
                for service in stats.services:
                    # Update error_rate
                    error_rate.labels(service=service.service).set(service.error_rate)
                    
                    # Update logs_total using deltas
                    levels = ["info", "warning", "error", "critical", "debug"]
                    for level in levels:
                        # getattr matches the field names in ServiceStats (info_count, etc.)
                        count = getattr(service, f"{level}_count", 0)
                        key = f"{service.service}_{level}"
                        last_count = last_counts.get(key, 0)
                        
                        if count > last_count:
                             logs_total.labels(service=service.service, level=level.upper()).inc(count - last_count)
                             last_counts[key] = count
                        elif count < last_count:
                             # DB reset or counter reset
                             last_counts[key] = count
                             
            await asyncio.sleep(15)
        except Exception as e:
            logger.error(f"Error updating prometheus metrics: {e}")
            await asyncio.sleep(15)


# -------------------------------------------------------------------
# Lifespan
# -------------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    global mongodb_client, aggregator_service, metrics_task

    logger.info("Starting Log Aggregator Service...")

    try:
        mongodb_client = MongoDBClient(
            connection_string=MONGODB_URI,
            database_name=MONGODB_DATABASE
        )
        aggregator_service = LogAggregatorService(mongodb_client)
        metrics_task = asyncio.create_task(update_prometheus_metrics())
        logger.info("Log Aggregator initialized successfully")

    except Exception as e:
        logger.error(f"Initialization failed: {e}")
        aggregator_service = None

    yield

    logger.info("Shutting down Log Aggregator Service...")
    if metrics_task:
        metrics_task.cancel()
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



# -------------------------------------------------------------------
# Basic Endpoints
# -------------------------------------------------------------------
@app.get("/")
async def root():
    return {"service": "log-aggregator", "status": "running"}


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "mongodb": mongodb_client is not None,
        "aggregator": aggregator_service is not None,
        "metrics": metrics_task is not None
    }


@app.get("/metrics", response_class=PlainTextResponse)
async def metrics():
    """Prometheus scrape endpoint"""
    return generate_latest()


# -------------------------------------------------------------------
# Stats APIs
# -------------------------------------------------------------------
@app.get("/api/stats/overall", response_model=AggregatedStats)
async def get_overall_stats():
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    return aggregator_service.get_overall_stats()


@app.get("/api/stats/timeseries")
async def get_time_series(
    hours: int = Query(24, ge=1, le=168),
    service: Optional[str] = Query(None)
):
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")

    data = aggregator_service.get_time_series(hours=hours, service=service)
    return {
        "hours": hours,
        "service": service or "all",
        "data": data
    }


@app.get("/api/stats/error-rate", response_model=ErrorRateResponse)
async def get_error_rate(
    service: Optional[str] = Query(None),
    hours: int = Query(24, ge=1, le=168)
):
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")
    return aggregator_service.get_error_rate(service=service, hours=hours)


@app.get("/api/stats/top-errors")
async def get_top_errors(limit: int = Query(10, ge=1, le=100)):
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")

    return {
        "limit": limit,
        "errors": aggregator_service.get_top_errors(limit=limit)
    }


@app.post("/api/aggregate/hourly")
async def trigger_hourly_aggregation():
    if not aggregator_service:
        raise HTTPException(status_code=503, detail="Aggregator service not available")

    aggregator_service.generate_hourly_aggregation()
    return {"success": True, "message": "Hourly aggregation completed"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)