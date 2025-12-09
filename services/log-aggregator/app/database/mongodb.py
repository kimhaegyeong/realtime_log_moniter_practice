"""
MongoDB 연결 및 쿼리
"""
import logging
from typing import Optional, List, Dict
from datetime import datetime, timedelta
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

logger = logging.getLogger(__name__)


class MongoDBClient:
    """MongoDB 클라이언트"""
    
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
        self.hourly_stats_collection = None
        
        self._connect()
    
    def _connect(self):
        """MongoDB 연결"""
        try:
            self.client = MongoClient(
                self.connection_string,
                serverSelectionTimeoutMS=5000
            )
            
            # 연결 테스트
            self.client.admin.command('ping')
            
            self.db = self.client[self.database_name]
            self.logs_collection = self.db["logs"]
            self.hourly_stats_collection = self.db["logs_hourly_stats"]
            
            logger.info(f"MongoDB connected: {self.database_name}")
            
        except ConnectionFailure as e:
            logger.error(f"Failed to connect to MongoDB: {e}")
            raise
    
    def get_total_count(self) -> int:
        """총 로그 개수"""
        try:
            return self.logs_collection.count_documents({})
        except Exception as e:
            logger.error(f"Error getting total count: {e}")
            return 0
    
    def get_service_stats(self) -> List[Dict]:
        """서비스별 통계"""
        try:
            pipeline = [
                {
                    "$group": {
                        "_id": "$service",
                        "total": {"$sum": 1},
                        "info": {
                            "$sum": {
                                "$cond": [{"$eq": ["$level", "INFO"]}, 1, 0]
                            }
                        },
                        "warning": {
                            "$sum": {
                                "$cond": [{"$eq": ["$level", "WARNING"]}, 1, 0]
                            }
                        },
                        "error": {
                            "$sum": {
                                "$cond": [{"$eq": ["$level", "ERROR"]}, 1, 0]
                            }
                        },
                        "critical": {
                            "$sum": {
                                "$cond": [{"$eq": ["$level", "CRITICAL"]}, 1, 0]
                            }
                        },
                        "debug": {
                            "$sum": {
                                "$cond": [{"$eq": ["$level", "DEBUG"]}, 1, 0]
                            }
                        }
                    }
                },
                {
                    "$project": {
                        "service": "$_id",
                        "total_logs": "$total",
                        "info_count": "$info",
                        "warning_count": "$warning",
                        "error_count": "$error",
                        "critical_count": "$critical",
                        "debug_count": "$debug",
                        "error_rate": {
                            "$multiply": [
                                {"$divide": [
                                    {"$add": ["$error", "$critical"]},
                                    "$total"
                                ]},
                                100
                            ]
                        }
                    }
                },
                {"$sort": {"total_logs": -1}}
            ]
            
            return list(self.logs_collection.aggregate(pipeline))
            
        except Exception as e:
            logger.error(f"Error getting service stats: {e}")
            return []
    
    def get_log_level_distribution(self) -> List[Dict]:
        """로그 레벨별 분포"""
        try:
            pipeline = [
                {
                    "$group": {
                        "_id": "$level",
                        "count": {"$sum": 1}
                    }
                },
                {"$sort": {"count": -1}}
            ]
            
            results = list(self.logs_collection.aggregate(pipeline))
            
            # 전체 로그 수
            total = sum(r["count"] for r in results)
            
            # 퍼센티지 계산
            for result in results:
                result["percentage"] = (result["count"] / total * 100) if total > 0 else 0
                result["level"] = result.pop("_id")
            
            return results
            
        except Exception as e:
            logger.error(f"Error getting log level distribution: {e}")
            return []
    
    def get_hourly_stats(
        self,
        hours: int = 24,
        service: Optional[str] = None
    ) -> List[Dict]:
        """
        시간대별 통계
        
        Args:
            hours: 과거 N시간
            service: 특정 서비스 필터
        """
        try:
            start_time = datetime.utcnow() - timedelta(hours=hours)
            
            match_stage = {"timestamp": {"$gte": start_time}}
            if service:
                match_stage["service"] = service
            
            pipeline = [
                {"$match": match_stage},
                {
                    "$group": {
                        "_id": {
                            "$dateToString": {
                                "format": "%Y-%m-%d-%H",
                                "date": "$timestamp"
                            }
                        },
                        "count": {"$sum": 1}
                    }
                },
                {"$sort": {"_id": 1}},
                {
                    "$project": {
                        "hour": "$_id",
                        "count": 1,
                        "_id": 0
                    }
                }
            ]
            
            return list(self.logs_collection.aggregate(pipeline))
            
        except Exception as e:
            logger.error(f"Error getting hourly stats: {e}")
            return []
    
    def get_error_rate(
        self,
        service: Optional[str] = None,
        hours: int = 24
    ) -> Dict:
        """에러율 계산"""
        try:
            start_time = datetime.utcnow() - timedelta(hours=hours)
            
            match_stage = {"timestamp": {"$gte": start_time}}
            if service:
                match_stage["service"] = service
            
            pipeline = [
                {"$match": match_stage},
                {
                    "$group": {
                        "_id": None,
                        "total": {"$sum": 1},
                        "errors": {
                            "$sum": {
                                "$cond": [
                                    {"$in": ["$level", ["ERROR", "CRITICAL"]]},
                                    1,
                                    0
                                ]
                            }
                        }
                    }
                },
                {
                    "$project": {
                        "total_logs": "$total",
                        "error_logs": "$errors",
                        "error_rate": {
                            "$multiply": [
                                {"$divide": ["$errors", "$total"]},
                                100
                            ]
                        }
                    }
                }
            ]
            
            result = list(self.logs_collection.aggregate(pipeline))
            
            if result:
                data = result[0]
                return {
                    "service": service or "all",
                    "total_logs": data["total_logs"],
                    "error_logs": data["error_logs"],
                    "error_rate": round(data["error_rate"], 2),
                    "period": f"last_{hours}_hours"
                }
            
            return {
                "service": service or "all",
                "total_logs": 0,
                "error_logs": 0,
                "error_rate": 0.0,
                "period": f"last_{hours}_hours"
            }
            
        except Exception as e:
            logger.error(f"Error calculating error rate: {e}")
            return {}
    
    def get_top_errors(self, limit: int = 10) -> List[Dict]:
        """빈도가 높은 에러 메시지"""
        try:
            pipeline = [
                {
                    "$match": {
                        "level": {"$in": ["ERROR", "CRITICAL"]}
                    }
                },
                {
                    "$group": {
                        "_id": {
                            "message": "$message",
                            "service": "$service"
                        },
                        "count": {"$sum": 1},
                        "last_occurred": {"$max": "$timestamp"}
                    }
                },
                {"$sort": {"count": -1}},
                {"$limit": limit},
                {
                    "$project": {
                        "message": "$_id.message",
                        "service": "$_id.service",
                        "count": 1,
                        "last_occurred": 1,
                        "_id": 0
                    }
                }
            ]
            
            return list(self.logs_collection.aggregate(pipeline))
            
        except Exception as e:
            logger.error(f"Error getting top errors: {e}")
            return []
    
    def save_hourly_stats(self, stats: Dict):
        """시간대별 통계 저장"""
        try:
            self.hourly_stats_collection.insert_one(stats)
            logger.debug(f"Hourly stats saved: {stats}")
        except Exception as e:
            logger.error(f"Error saving hourly stats: {e}")
    
    def close(self):
        """연결 종료"""
        if self.client:
            self.client.close()
            logger.info("MongoDB connection closed")