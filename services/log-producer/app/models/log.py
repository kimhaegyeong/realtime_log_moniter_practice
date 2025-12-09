"""
로그 데이터 모델 정의
"""
from datetime import datetime
from typing import Optional, Dict, Any
from pydantic import BaseModel, Field, ConfigDict
from enum import Enum


class LogLevel(str, Enum):
    """로그 레벨"""
    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class ServiceName(str, Enum):
    """서비스 이름"""
    API_SERVICE = "api-service"
    AUTH_SERVICE = "auth-service"
    PAYMENT_SERVICE = "payment-service"


class LogEntry(BaseModel):
    """로그 엔트리 모델"""
    model_config = ConfigDict(
        json_encoders={
            datetime: lambda v: v.isoformat()
        }
    )
    
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    level: LogLevel
    service: ServiceName
    message: str
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict)
    
    def to_dict(self) -> dict:
        """딕셔너리로 변환"""
        return {
            "timestamp": self.timestamp.isoformat(),
            "level": self.level.value,
            "service": self.service.value,
            "message": self.message,
            "metadata": self.metadata
        }


class LogRequest(BaseModel):
    """API 요청 모델"""
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "level": "INFO",
                "service": "api-service",
                "message": "User login successful",
                "metadata": {
                    "user_id": "12345",
                    "ip": "192.168.1.1"
                }
            }
        }
    )
    
    level: LogLevel
    service: ServiceName
    message: str
    metadata: Optional[Dict[str, Any]] = None


class LogResponse(BaseModel):
    """API 응답 모델"""
    success: bool
    message: str
    log_id: Optional[str] = None