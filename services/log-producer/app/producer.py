"""
Kafka Producer 구현
"""
import json
import logging
from typing import Optional
from kafka import KafkaProducer
from kafka.errors import KafkaError
from app.models.log import LogEntry

logger = logging.getLogger(__name__)


class LogProducer:
    """Kafka 로그 프로듀서"""
    
    def __init__(self, bootstrap_servers: str, topic: str):
        """
        Args:
            bootstrap_servers: Kafka 브로커 주소
            topic: 전송할 토픽 이름
        """
        self.topic = topic
        self.producer: Optional[KafkaProducer] = None
        self.bootstrap_servers = bootstrap_servers
        
        try:
            self.producer = KafkaProducer(
                bootstrap_servers=bootstrap_servers,
                value_serializer=lambda v: json.dumps(v).encode('utf-8'),
                # 성능 최적화 설정
                acks='all',
                retries=3,
                max_in_flight_requests_per_connection=5,
                compression_type='gzip',
                linger_ms=10,
                batch_size=16384,
            )
            logger.info(f"Kafka Producer initialized: {bootstrap_servers}, topic: {topic}")
        except Exception as e:
            logger.error(f"Failed to initialize Kafka Producer: {e}")
            raise
    
    def send_log(self, log_entry: LogEntry) -> bool:
        """
        로그를 Kafka로 전송
        
        Args:
            log_entry: 전송할 로그 엔트리
            
        Returns:
            성공 여부
        """
        if not self.producer:
            logger.error("Kafka Producer is not initialized")
            return False
        
        try:
            log_dict = log_entry.to_dict()
            future = self.producer.send(self.topic, value=log_dict)
            record_metadata = future.get(timeout=10)
            
            logger.debug(
                f"Log sent to Kafka - "
                f"Topic: {record_metadata.topic}, "
                f"Partition: {record_metadata.partition}, "
                f"Offset: {record_metadata.offset}"
            )
            return True
            
        except KafkaError as e:
            logger.error(f"Kafka error while sending log: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error while sending log: {e}")
            return False
    
    def send_batch(self, log_entries: list[LogEntry]) -> tuple[int, int]:
        """
        여러 로그를 배치로 전송
        
        Args:
            log_entries: 로그 엔트리 리스트
            
        Returns:
            (성공 개수, 실패 개수)
        """
        success_count = 0
        failure_count = 0
        
        for log_entry in log_entries:
            if self.send_log(log_entry):
                success_count += 1
            else:
                failure_count += 1
        
        self.producer.flush()
        
        logger.info(f"Batch send completed - Success: {success_count}, Failed: {failure_count}")
        return success_count, failure_count
    
    def close(self):
        """Producer 종료"""
        if self.producer:
            self.producer.flush()
            self.producer.close()
            logger.info("Kafka Producer closed")
    
    def __enter__(self):
        """Context manager 진입"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager 종료"""
        self.close()
