"""
로그 집계 서비스
"""
import logging
from datetime import datetime
from typing import Optional, List
from app.database.mongodb import MongoDBClient
from app.models.stats import (
    ServiceStats,
    LogLevelDistribution,
    AggregatedStats,
    TimeSeriesData,
    ErrorRateResponse,
    TopErrorsResponse
)

logger = logging.getLogger(__name__)


class LogAggregatorService:
    """로그 집계 서비스"""
    
    def __init__(self, mongodb_client: MongoDBClient):
        """
        Args:
            mongodb_client: MongoDB 클라이언트
        """
        self.db = mongodb_client
    
    def get_overall_stats(self) -> AggregatedStats:
        """전체 통계 조회"""
        try:
            # 총 로그 수
            total_logs = self.db.get_total_count()
            
            # 서비스별 통계
            service_stats_data = self.db.get_service_stats()
            services = [
                ServiceStats(
                    service=s["service"],
                    total_logs=s["total_logs"],
                    info_count=s.get("info_count", 0),
                    warning_count=s.get("warning_count", 0),
                    error_count=s.get("error_count", 0),
                    critical_count=s.get("critical_count", 0),
                    debug_count=s.get("debug_count", 0),
                    error_rate=round(s.get("error_rate", 0), 2)
                )
                for s in service_stats_data
            ]
            
            # 로그 레벨 분포
            level_dist_data = self.db.get_log_level_distribution()
            log_level_distribution = [
                LogLevelDistribution(
                    level=d["level"],
                    count=d["count"],
                    percentage=round(d["percentage"], 2)
                )
                for d in level_dist_data
            ]
            
            return AggregatedStats(
                total_logs=total_logs,
                services=services,
                log_level_distribution=log_level_distribution,
                time_range={
                    "start": "all",
                    "end": datetime.utcnow().isoformat()
                }
            )
            
        except Exception as e:
            logger.error(f"Error getting overall stats: {e}")
            raise
    
    def get_time_series(
        self,
        hours: int = 24,
        service: Optional[str] = None
    ) -> List[TimeSeriesData]:
        """시계열 데이터 조회"""
        try:
            hourly_data = self.db.get_hourly_stats(hours=hours, service=service)
            
            return [
                TimeSeriesData(
                    timestamp=d["hour"],
                    count=d["count"]
                )
                for d in hourly_data
            ]
            
        except Exception as e:
            logger.error(f"Error getting time series: {e}")
            return []
    
    def get_error_rate(
        self,
        service: Optional[str] = None,
        hours: int = 24
    ) -> ErrorRateResponse:
        """에러율 조회"""
        try:
            data = self.db.get_error_rate(service=service, hours=hours)
            
            return ErrorRateResponse(
                service=data.get("service", "all"),
                total_logs=data.get("total_logs", 0),
                error_logs=data.get("error_logs", 0),
                error_rate=data.get("error_rate", 0.0),
                period=data.get("period", f"last_{hours}_hours")
            )
            
        except Exception as e:
            logger.error(f"Error getting error rate: {e}")
            raise
    
    def get_top_errors(self, limit: int = 10) -> List[TopErrorsResponse]:
        """Top 에러 조회"""
        try:
            errors_data = self.db.get_top_errors(limit=limit)
            
            return [
                TopErrorsResponse(
                    message=e["message"],
                    count=e["count"],
                    service=e["service"],
                    last_occurred=e["last_occurred"]
                )
                for e in errors_data
            ]
            
        except Exception as e:
            logger.error(f"Error getting top errors: {e}")
            return []
    
    def generate_hourly_aggregation(self):
        """시간대별 집계 생성 (스케줄러용)"""
        try:
            logger.info("Generating hourly aggregation...")
            
            # 1시간 단위 통계 생성
            hourly_data = self.db.get_hourly_stats(hours=1)
            
            for data in hourly_data:
                stats = {
                    "hour": data["hour"],
                    "count": data["count"],
                    "generated_at": datetime.utcnow()
                }
                self.db.save_hourly_stats(stats)
            
            logger.info(f"Hourly aggregation completed: {len(hourly_data)} entries")
            
        except Exception as e:
            logger.error(f"Error generating hourly aggregation: {e}")