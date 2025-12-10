FROM python:3.11-slim

WORKDIR /app

# 시스템 패키지 업데이트
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Python 의존성 설치
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 애플리케이션 코드 복사
COPY app ./app

# 비-root 유저 생성
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# 애플리케이션 실행
CMD ["python", "-m", "app.main"]