# load_test.py
import requests
import time
import random
from concurrent.futures import ThreadPoolExecutor

def send_logs(duration_seconds, logs_per_second):
    start_time = time.time()

    while time.time() - start_time < duration_seconds:
        batch_start = time.time()

        # 1초에 logs_per_second개 전송
        for _ in range(logs_per_second):
            requests.post('http://localhost:8000/api/logs/generate',
                        json={'count': 1})

        # 1초 맞추기
        elapsed = time.time() - batch_start
        if elapsed < 1:
            time.sleep(1 - elapsed)

if __name__ == '__main__':
    print("Starting load test: 1000 logs/second for 60 seconds")
    send_logs(duration_seconds=60, logs_per_second=1000)
    print("Load test completed")
