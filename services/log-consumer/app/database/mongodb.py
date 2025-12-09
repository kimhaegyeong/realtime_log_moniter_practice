"""
MongoDB 연결 및 데이터 저장
"""
import logging
from typing import List, Optional
from pymongo import MongoClient, ASCENDING, DESCENDING
from pymongo.errors import ConnectionFailure, BulkWriteError
from app.models.log import LogEntry

logger = logging.getLogger(__name__)


class MongoDBHandler:
    """MongoDB 핸들러"""
    
    def __init__(self, connection_string: str, database_name: str = "logs"):
        """
        Args:
            connection_string: MongoDB 연결 문자열
            database_name: 데이터베이스 이름
        """
        self.connection_string = connection_string
        self.database_name = database_name
        self.client: Optional[MongoClient] = None
        self.db = None
        self.logs_collection = None
        
        self._connect()
    
    def _connect(self):
        """MongoDB 연결"""
        try:
            self.client = MongoClient(
                self.connection_string,
                serverSelectionTimeoutMS=5000,
                connectTimeoutMS=10000,
                socketTimeoutMS=10000,
            )
            
            # 연결 테스트
            self.client.admin.command('ping')
            
            self.db = self.client[self.database_name]
            self.logs_collection = self.db["logs"]
            
            # 인덱스 생성
            self._create_indexes()
            
            logger.info(f"MongoDB connected: {self.database_name}")
            
        except ConnectionFailure as e:
            logger.error(f"Failed to connect to MongoDB: {e}")
            raise
    
    def _create_indexes(self):
        """인덱스 생성"""
        try:
            # 타임스탬프 인덱스 (내림차순 - 최신 로그 빠른 조회)
            self.logs_collection.create_index(
                [("timestamp", DESCENDING)]
            )
            
            # 서비스별 타임스탬프 인덱스
            self.logs_collection.create_index(
                [("service", ASCENDING), ("timestamp", DESCENDING)]
            )
            
            # 로그 레벨별 타임스탬프 인덱스
            self.logs_collection.create_index(
                [("level", ASCENDING), ("timestamp", DESCENDING)]
            )
            
            # 복합 인덱스 (서비스 + 레벨)
            self.logs_collection.create_index(
                [("service", ASCENDING), ("level", ASCENDING)]
            )
            
            logger.info("MongoDB indexes created successfully")
            
        except Exception as e:
            logger.error(f"Failed to create indexes: {e}")
    
    def insert_log(self, log_entry: LogEntry) -> bool:
        """
        단일 로그 저장
        
        Args:
            log_entry: 저장할 로그 엔트리
            
        Returns:
            성공 여부
        """
        try:
            log_dict = log_entry.to_mongo_dict()
            result = self.logs_collection.insert_one(log_dict)
            
            logger.debug(f"Log inserted with id: {result.inserted_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to insert log: {e}")
            return False
    
    def insert_logs_batch(self, log_entries: List[LogEntry]) -> tuple[int, int]:
        """
        배치로 로그 저장 (성능 최적화)
        
        Args:
            log_entries: 저장할 로그 엔트리 리스트
            
        Returns:
            (성공 개수, 실패 개수)
        """
        if not log_entries:
            return 0, 0
        
        try:
            log_dicts = [log.to_mongo_dict() for log in log_entries]
            result = self.logs_collection.insert_many(log_dicts, ordered=False)
            
            success_count = len(result.inserted_ids)
            failure_count = len(log_entries) - success_count
            
            logger.info(f"Batch insert: {success_count} succeeded, {failure_count} failed")
            return success_count, failure_count
            
        except BulkWriteError as e:
            # 일부 성공, 일부 실패
            success_count = e.details.get('nInserted', 0)
            failure_count = len(log_entries) - success_count
            
            logger.warning(f"Partial batch insert: {success_count} succeeded, {failure_count} failed")
            return success_count, failure_count
            
        except Exception as e:
            logger.error(f"Failed to insert batch: {e}")
            return 0, len(log_entries)
    
    def get_logs(self, limit: int = 100, skip: int = 0) -> List[dict]:
        """
        로그 조회
        
        Args:
            limit: 조회할 개수
            skip: 건너뛸 개수
            
        Returns:
            로그 리스트
        """
        try:
            logs = list(
                self.logs_collection
                .find()
                .sort("timestamp", DESCENDING)
                .skip(skip)
                .limit(limit)
            )
            
            # ObjectId를 문자열로 변환
            for log in logs:
                log['_id'] = str(log['_id'])
            
            return logs
            
        except Exception as e:
            logger.error(f"Failed to get logs: {e}")
            return []
    
    def get_logs_by_service(self, service: str, limit: int = 100) -> List[dict]:
        """서비스별 로그 조회"""
        try:
            logs = list(
                self.logs_collection
                .find({"service": service})
                .sort("timestamp", DESCENDING)
                .limit(limit)
            )
            
            for log in logs:
                log['_id'] = str(log['_id'])
            
            return logs
            
        except Exception as e:
            logger.error(f"Failed to get logs by service: {e}")
            return []
    
    def get_logs_by_level(self, level: str, limit: int = 100) -> List[dict]:
        """로그 레벨별 조회"""
        try:
            logs = list(
                self.logs_collection
                .find({"level": level})
                .sort("timestamp", DESCENDING)
                .limit(limit)
            )
            
            for log in logs:
                log['_id'] = str(log['_id'])
            
            return logs
            
        except Exception as e:
            logger.error(f"Failed to get logs by level: {e}")
            return []
    
    def get_log_count(self) -> int:
        """총 로그 개수"""
        try:
            return self.logs_collection.count_documents({})
        except Exception as e:
            logger.error(f"Failed to get log count: {e}")
            return 0
    
    def get_stats(self) -> dict:
        """로그 통계"""
        try:
            pipeline = [
                {
                    "$group": {
                        "_id": {
                            "service": "$service",
                            "level": "$level"
                        },
                        "count": {"$sum": 1}
                    }
                }
            ]
            
            result = list(self.logs_collection.aggregate(pipeline))
            
            stats = {
                "total": self.get_log_count(),
                "by_service_and_level": result
            }
            
            return stats
            
        except Exception as e:
            logger.error(f"Failed to get stats: {e}")
            return {"total": 0, "by_service_and_level": []}
    
    def close(self):
        """연결 종료"""
        if self.client:
            self.client.close()
            logger.info("MongoDB connection closed")