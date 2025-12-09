"""
랜덤 로그 데이터 생성기
"""
import random
from datetime import datetime
from typing import Dict, Any
from app.models.log import LogEntry, LogLevel, ServiceName


class LogGenerator:
    """로그 생성기 클래스"""
    
    # 서비스별 메시지 템플릿
    MESSAGE_TEMPLATES = {
        ServiceName.API_SERVICE: [
            "User login successful",
            "API request processed",
            "Database query executed",
            "Cache hit for key",
            "Request rate limit exceeded",
            "Invalid request parameters",
            "API endpoint not found",
            "Authentication token validated",
        ],
        ServiceName.AUTH_SERVICE: [
            "User authentication successful",
            "Password reset requested",
            "Two-factor authentication enabled",
            "Session expired",
            "Invalid credentials provided",
            "User account locked",
            "OAuth token generated",
            "Refresh token invalidated",
        ],
        ServiceName.PAYMENT_SERVICE: [
            "Payment processed successfully",
            "Transaction initiated",
            "Payment gateway timeout",
            "Refund issued",
            "Insufficient funds",
            "Card validation failed",
            "Payment method updated",
            "Subscription renewed",
        ]
    }
    
    # 로그 레벨 분포 (실제와 유사하게)
    LOG_LEVEL_WEIGHTS = {
        LogLevel.DEBUG: 5,
        LogLevel.INFO: 70,
        LogLevel.WARNING: 15,
        LogLevel.ERROR: 8,
        LogLevel.CRITICAL: 2,
    }
    
    @staticmethod
    def generate_user_id() -> str:
        """랜덤 사용자 ID 생성"""
        return f"user_{random.randint(10000, 99999)}"
    
    @staticmethod
    def generate_ip() -> str:
        """랜덤 IP 주소 생성"""
        return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 255)}"
    
    @staticmethod
    def generate_request_id() -> str:
        """랜덤 요청 ID 생성"""
        return f"req_{random.randint(100000, 999999)}"
    
    @staticmethod
    def generate_metadata(service: ServiceName, level: LogLevel) -> Dict[str, Any]:
        """서비스와 로그 레벨에 따른 메타데이터 생성"""
        metadata = {
            "request_id": LogGenerator.generate_request_id(),
            "user_id": LogGenerator.generate_user_id(),
            "ip": LogGenerator.generate_ip(),
        }
        
        # 서비스별 추가 메타데이터
        if service == ServiceName.API_SERVICE:
            metadata.update({
                "endpoint": random.choice(["/api/users", "/api/products", "/api/orders"]),
                "method": random.choice(["GET", "POST", "PUT", "DELETE"]),
                "status_code": random.choice([200, 201, 400, 404, 500]),
                "response_time_ms": random.randint(10, 500),
            })
        
        elif service == ServiceName.AUTH_SERVICE:
            metadata.update({
                "auth_method": random.choice(["password", "oauth", "2fa"]),
                "session_id": f"sess_{random.randint(100000, 999999)}",
            })
        
        elif service == ServiceName.PAYMENT_SERVICE:
            metadata.update({
                "transaction_id": f"txn_{random.randint(100000, 999999)}",
                "amount": round(random.uniform(10.0, 1000.0), 2),
                "currency": random.choice(["USD", "EUR", "KRW"]),
                "payment_method": random.choice(["card", "paypal", "bank_transfer"]),
            })
        
        # 에러 레벨인 경우 에러 정보 추가
        if level in [LogLevel.ERROR, LogLevel.CRITICAL]:
            metadata.update({
                "error_code": f"ERR_{random.randint(1000, 9999)}",
                "stack_trace": "...[truncated]...",
            })
        
        return metadata
    
    @classmethod
    def generate_log(cls, service: ServiceName = None, level: LogLevel = None) -> LogEntry:
        """랜덤 로그 엔트리 생성"""
        # 서비스 선택 (제공되지 않은 경우)
        if service is None:
            service = random.choice(list(ServiceName))
        
        # 로그 레벨 선택 (가중치 적용)
        if level is None:
            levels = list(cls.LOG_LEVEL_WEIGHTS.keys())
            weights = list(cls.LOG_LEVEL_WEIGHTS.values())
            level = random.choices(levels, weights=weights)[0]
        
        # 메시지 선택
        message = random.choice(cls.MESSAGE_TEMPLATES[service])
        
        # 메타데이터 생성
        metadata = cls.generate_metadata(service, level)
        
        return LogEntry(
            timestamp=datetime.utcnow(),
            level=level,
            service=service,
            message=message,
            metadata=metadata
        )
    
    @classmethod
    def generate_batch(cls, count: int, service: ServiceName = None) -> list[LogEntry]:
        """배치로 로그 생성"""
        return [cls.generate_log(service=service) for _ in range(count)]