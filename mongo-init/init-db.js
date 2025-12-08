db = db.getSiblingDB('logs');

// 컬렉션 생성
db.createCollection('logs');
db.createCollection('logs_hourly_stats');

// 인덱스 생성 (성능 최적화)
db.logs.createIndex({ "timestamp": -1 });
db.logs.createIndex({ "service": 1, "timestamp": -1 });
db.logs.createIndex({ "level": 1, "timestamp": -1 });
db.logs.createIndex({ "service": 1, "level": 1 });

db.logs_hourly_stats.createIndex({ "hour": -1 });
db.logs_hourly_stats.createIndex({ "service": 1, "hour": -1 });
