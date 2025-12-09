"""
자동 로그 생성기 (백그라운드 실행)
"""
import asyncio
import logging
import os
from app.utils.generator import LogGenerator
from app.models.log import ServiceName
from app.producer import LogProducer

logger = logging.getLogger(__name__)


class AutoLogGenerator:
    """자동 로그 생성기"""
    
    def __init__(
        self,
        producer: LogProducer,
        service: ServiceName,
        logs_per_second: int = 1
    ):
        """
        Args:
            producer: Kafka Producer
            service: 생성할 서비스 이름
            logs_per_second: 초당 생성할 로그 개수
        """
        self.producer = producer
        self.service = service
        self.logs_per_second = logs_per_second
        self.is_running = False
        self.total_sent = 0
        
    async def start(self):
        """자동 로그 생성 시작"""
        self.is_running = True
        logger.info(
            f"Auto log generation started - "
            f"Service: {self.service.value}, "
            f"Rate: {self.logs_per_second} logs/sec"
        )
        
        interval = 1.0 / self.logs_per_second
        
        while self.is_running:
            try:
                # 로그 생성
                log_entry = LogGenerator.generate_log(service=self.service)
                
                # Kafka로 전송
                success = self.producer.send_log(log_entry)
                
                if success:
                    self.total_sent += 1
                    
                    # 100개마다 통계 출력
                    if self.total_sent % 100 == 0:
                        logger.info(
                            f"[{self.service.value}] Total sent: {self.total_sent}"
                        )
                
                # 대기
                await asyncio.sleep(interval)
                
            except Exception as e:
                logger.error(f"Error generating log: {e}")
                await asyncio.sleep(1)
    
    def stop(self):
        """자동 로그 생성 중지"""
        self.is_running = False
        logger.info(
            f"Auto log generation stopped - "
            f"Service: {self.service.value}, "
            f"Total sent: {self.total_sent}"
        )
