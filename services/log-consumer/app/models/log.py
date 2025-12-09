"""
로그 데이터 모델 (Consumer용)
"""
from datetime import datetime
from typing import Optional, Dict, Any
from pydantic import BaseModel, Field, ConfigDict


class LogEntry(BaseModel):
    """로그 엔트리 모델"""
    model_config = ConfigDict(
        json_encoders={
            datetime: lambda v: v.isoformat() if v else None
        }
    )
    
    timestamp: datetime
    level: str
    service: str
    message: str
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict)
    
    @classmethod
    def from_kafka_message(cls, message_value: dict) -> "LogEntry":
        """
        Kafka 메시지에서 LogEntry 생성
        
        Args:
            message_value: Kafka 메시지의 value (dict)
            
        Returns:
            LogEntry 인스턴스
        """
        # timestamp가 문자열이면 datetime으로 변환
        timestamp = message_value.get("timestamp")
        if isinstance(timestamp, str):
            timestamp = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        elif not isinstance(timestamp, datetime):
            timestamp = datetime.utcnow()
        
        return cls(
            timestamp=timestamp,
            level=message_value.get("level", "INFO"),
            service=message_value.get("service", "unknown"),
            message=message_value.get("message", ""),
            metadata=message_value.get("metadata", {})
        )
    
    def to_mongo_dict(self) -> dict:
        """MongoDB 저장용 딕셔너리로 변환"""
        return {
            "timestamp": self.timestamp,
            "level": self.level,
            "service": self.service,
            "message": self.message,
            "metadata": self.metadata,
            "created_at": datetime.utcnow()
        }