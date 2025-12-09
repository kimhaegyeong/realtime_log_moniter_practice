"""
Kafka Consumer 구현
"""
import json
import logging
from typing import Optional
from kafka import KafkaConsumer
from kafka.errors import KafkaError
from app.models.log import LogEntry
from app.database.mongodb import MongoDBHandler

logger = logging.getLogger(__name__)


def safe_json_deserializer(m):
    """안전한 JSON 역직렬화"""
    if m is None:
        return None
    try:
        return json.loads(m.decode('utf-8'))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


class LogConsumer:
    """Kafka 로그 컨슈머"""
    
    def __init__(
        self,
        bootstrap_servers: str,
        topic: str,
        group_id: str,
        mongodb_handler: MongoDBHandler,
        batch_size: int = 100
    ):
        """
        Args:
            bootstrap_servers: Kafka 브로커 주소
            topic: 구독할 토픽 이름
            group_id: Consumer Group ID
            mongodb_handler: MongoDB 핸들러
            batch_size: 배치 저장 크기
        """
        self.bootstrap_servers = bootstrap_servers
        self.topic = topic
        self.group_id = group_id
        self.mongodb_handler = mongodb_handler
        self.batch_size = batch_size
        self.consumer: Optional[KafkaConsumer] = None
        
        # 통계
        self.total_processed = 0
        self.total_success = 0
        self.total_failed = 0
        
        self._create_consumer()
    
    def _create_consumer(self):
        """Kafka Consumer 생성"""
        try:
            self.consumer = KafkaConsumer(
                self.topic,
                bootstrap_servers=self.bootstrap_servers,
                group_id=self.group_id,
                # 메시지 처리 설정
                auto_offset_reset='earliest',  # 처음부터 읽기
                enable_auto_commit=True,  # 자동 offset commit
                auto_commit_interval_ms=5000,  # 5초마다 commit
                # 역직렬화
                value_deserializer=safe_json_deserializer,
                # 성능 설정
                max_poll_records=self.batch_size,  # 한 번에 가져올 최대 레코드 수
                session_timeout_ms=30000,  # 30초
                heartbeat_interval_ms=10000,  # 10초
            )
            
            logger.info(
                f"Kafka Consumer created - "
                f"Topic: {self.topic}, Group: {self.group_id}, "
                f"Batch size: {self.batch_size}"
            )
            
        except Exception as e:
            logger.error(f"Failed to create Kafka Consumer: {e}")
            raise
    
    def consume_messages(self):
        """
        메시지 소비 및 MongoDB 저장 (무한 루프)
        """
        logger.info("Starting message consumption...")
        
        batch = []
        
        try:
            for message in self.consumer:
                try:
                    # 메시지 값이 없으면 스킵 (역직렬화 실패 등)
                    if message.value is None:
                        continue

                    # Kafka 메시지를 LogEntry로 변환
                    log_entry = LogEntry.from_kafka_message(message.value)
                    batch.append(log_entry)
                    
                    logger.debug(
                        f"Received log - "
                        f"Partition: {message.partition}, "
                        f"Offset: {message.offset}, "
                        f"Service: {log_entry.service}"
                    )
                    
                    # 배치 크기에 도달하면 저장
                    if len(batch) >= self.batch_size:
                        self._save_batch(batch)
                        batch = []
                    
                except Exception as e:
                    logger.error(f"Error processing message: {e}")
                    self.total_failed += 1
                    continue
                    
        except KeyboardInterrupt:
            logger.info("Consumer interrupted by user")
            
        finally:
            # 남은 배치 저장
            if batch:
                self._save_batch(batch)
            
            self._print_stats()
            self.close()
    
    def _save_batch(self, batch: list[LogEntry]):
        """배치를 MongoDB에 저장"""
        if not batch:
            return
        
        try:
            success_count, failure_count = self.mongodb_handler.insert_logs_batch(batch)
            
            self.total_processed += len(batch)
            self.total_success += success_count
            self.total_failed += failure_count
            
            logger.info(
                f"Batch saved - "
                f"Size: {len(batch)}, "
                f"Success: {success_count}, "
                f"Failed: {failure_count}, "
                f"Total processed: {self.total_processed}"
            )
            
        except Exception as e:
            logger.error(f"Failed to save batch: {e}")
            self.total_failed += len(batch)
    
    def _print_stats(self):
        """통계 출력"""
        logger.info("=" * 50)
        logger.info("Consumer Statistics")
        logger.info(f"Total processed: {self.total_processed}")
        logger.info(f"Total success: {self.total_success}")
        logger.info(f"Total failed: {self.total_failed}")
        
        if self.total_processed > 0:
            success_rate = (self.total_success / self.total_processed) * 100
            logger.info(f"Success rate: {success_rate:.2f}%")
        
        logger.info("=" * 50)
    
    def close(self):
        """Consumer 종료"""
        if self.consumer:
            self.consumer.close()
            logger.info("Kafka Consumer closed")
    
    def __enter__(self):
        """Context manager 진입"""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager 종료"""
        self.close()