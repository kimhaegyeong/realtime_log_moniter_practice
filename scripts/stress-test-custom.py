#!/usr/bin/env python3
"""
Custom stress test for log monitoring system
Target: 10,000 logs/second
"""
import asyncio
import aiohttp
import time
import random
from datetime import datetime
import json

BASE_URL = "http://localhost:8000"
TARGET_RPS = 10000  # Requests per second
DURATION = 60  # Test duration in seconds

SERVICES = ["api-service", "auth-service", "payment-service"]
LEVELS = ["INFO", "DEBUG", "WARNING", "ERROR", "CRITICAL"]
LEVEL_WEIGHTS = [70, 5, 15, 8, 2]  # Percentage distribution

# Statistics
stats = {
    "total_sent": 0,
    "total_success": 0,
    "total_failed": 0,
    "start_time": None,
    "end_time": None,
}

async def send_log(session, semaphore):
    """Send a single log"""
    async with semaphore:
        service = random.choice(SERVICES)
        level = random.choices(LEVELS, weights=LEVEL_WEIGHTS)[0]
        
        payload = {
            "level": level,
            "service": service,
            "message": f"Stress test message {random.randint(1000, 9999)}",
            "metadata": {
                "test": True,
                "timestamp": time.time(),
                "user_id": f"test_user_{random.randint(1, 1000)}"
            }
        }
        
        try:
            async with session.post(
                f"{BASE_URL}/api/logs",
                json=payload,
                timeout=aiohttp.ClientTimeout(total=5)
            ) as response:
                stats["total_sent"] += 1
                if response.status == 200:
                    stats["total_success"] += 1
                else:
                    stats["total_failed"] += 1
                    
        except Exception as e:
            stats["total_sent"] += 1
            stats["total_failed"] += 1

async def send_batch(session, semaphore, size=100):
    """Send batch logs"""
    async with semaphore:
        service = random.choice(SERVICES)
        
        try:
            async with session.post(
                f"{BASE_URL}/api/logs/batch",
                params={"count": size, "service": service},
                timeout=aiohttp.ClientTimeout(total=10)
            ) as response:
                if response.status == 200:
                    stats["total_sent"] += size
                    stats["total_success"] += size
                else:
                    stats["total_sent"] += size
                    stats["total_failed"] += size
                    
        except Exception as e:
            stats["total_sent"] += size
            stats["total_failed"] += size

async def producer(session, semaphore, rps, duration):
    """Produce logs at specified rate"""
    interval = 1.0 / rps
    end_time = time.time() + duration
    
    tasks = []
    
    while time.time() < end_time:
        # 90% single logs, 10% batch
        if random.random() < 0.9:
            task = asyncio.create_task(send_log(session, semaphore))
        else:
            task = asyncio.create_task(send_batch(session, semaphore, size=50))
        
        tasks.append(task)
        
        # Print progress every second
        if len(tasks) % 1000 == 0:
            elapsed = time.time() - stats["start_time"]
            current_rps = stats["total_sent"] / elapsed if elapsed > 0 else 0
            print(f"Progress: {stats['total_sent']} logs sent, "
                  f"Current rate: {current_rps:.0f} logs/sec")
        
        await asyncio.sleep(interval)
    
    # Wait for all tasks to complete
    await asyncio.gather(*tasks, return_exceptions=True)

async def main():
    """Main test function"""
    print("=" * 60)
    print("Custom Stress Test")
    print("=" * 60)
    print(f"Target: {TARGET_RPS} logs/second")
    print(f"Duration: {DURATION} seconds")
    print(f"Expected total: {TARGET_RPS * DURATION} logs")
    print("=" * 60)
    print()
    
    stats["start_time"] = time.time()
    
    # Connection pool
    connector = aiohttp.TCPConnector(limit=500, limit_per_host=500)
    semaphore = asyncio.Semaphore(500)  # Max concurrent requests
    
    async with aiohttp.ClientSession(connector=connector) as session:
        await producer(session, semaphore, TARGET_RPS, DURATION)
    
    stats["end_time"] = time.time()
    
    # Print results
    print("\n" + "=" * 60)
    print("Test Results")
    print("=" * 60)
    
    elapsed = stats["end_time"] - stats["start_time"]
    actual_rps = stats["total_sent"] / elapsed
    success_rate = (stats["total_success"] / stats["total_sent"] * 100) if stats["total_sent"] > 0 else 0
    
    print(f"Duration: {elapsed:.2f} seconds")
    print(f"Total sent: {stats['total_sent']}")
    print(f"Success: {stats['total_success']}")
    print(f"Failed: {stats['total_failed']}")
    print(f"Success rate: {success_rate:.2f}%")
    print(f"Actual throughput: {actual_rps:.0f} logs/second")
    print(f"Target: {TARGET_RPS} logs/second")
    
    if actual_rps >= TARGET_RPS * 0.9:
        print("\n✅ SUCCESS: Target throughput achieved!")
    else:
        print(f"\n⚠️  WARNING: Only {(actual_rps/TARGET_RPS)*100:.1f}% of target achieved")
    
    print("=" * 60)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        print(f"Logs sent: {stats['total_sent']}")
