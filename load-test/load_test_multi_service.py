import requests
import time
import random

SERVICES = {
    "api-service": {"INFO": 0.8, "WARNING": 0.15, "ERROR": 0.05},
    "auth-service": {"INFO": 0.7, "WARNING": 0.2, "ERROR": 0.1},
    "payment-service": {"INFO": 0.9, "WARNING": 0.05, "ERROR": 0.05},
}

def pick_level(weights):
    r = random.random()
    acc = 0
    for level, w in weights.items():
        acc += w
        if r <= acc:
            return level

def send_logs(duration, logs_per_second):
    start = time.time()

    while time.time() - start < duration:
        batch_start = time.time()

        for _ in range(logs_per_second):
            service = random.choice(list(SERVICES.keys()))
            level = pick_level(SERVICES[service])

            requests.post(
                "http://localhost:8000/api/logs/generate",
                json={
                    "service": service,
                    "level": level,
                    "message": "load test log"
                }
            )

        elapsed = time.time() - batch_start
        if elapsed < 1:
            time.sleep(1 - elapsed)


if __name__ == '__main__':
    print("Starting load test: 1000 logs/second for 60 seconds")
    send_logs(duration=60, logs_per_second=1000)
    print("Load test completed")

