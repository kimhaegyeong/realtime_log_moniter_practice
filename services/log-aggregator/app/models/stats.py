"""
통계 데이터 모델
"""
from datetime import datetime
from typing import Optional, List, Dict
from pydantic import BaseModel, Field, ConfigDict


class ServiceStats(BaseModel):
    """서비스별 통계"""
    service: str
    total_logs: int
    info_count: int = 0
    warning_count: int = 0
    error_count: int = 0
    critical_count: int = 0
    debug_count: int = 0
    error_rate: float = 0.0  # 에러 비율 (%)


class HourlyStats(BaseModel):
    """시간대별 통계"""
    hour: str  # YYYY-MM-DD-HH 형식
    service: Optional[str] = None
    level: Optional[str] = None
    count: int
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class LogLevelDistribution(BaseModel):
    """로그 레벨별 분포"""
    level: str
    count: int
    percentage: float


class TimeSeriesData(BaseModel):
    """시계열 데이터"""
    timestamp: str
    count: int


class AggregatedStats(BaseModel):
    """전체 집계 통계"""
    total_logs: int
    services: List[ServiceStats]
    log_level_distribution: List[LogLevelDistribution]
    time_range: Dict[str, str]  # start, end
    generated_at: datetime = Field(default_factory=datetime.utcnow)


class ErrorRateResponse(BaseModel):
    """에러율 응답"""
    service: str
    total_logs: int
    error_logs: int
    error_rate: float
    period: str


class TopErrorsResponse(BaseModel):
    """Top 에러 응답"""
    message: str
    count: int
    service: str
    last_occurred: datetime