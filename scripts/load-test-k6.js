import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// 커스텀 메트릭
const errorRate = new Rate('errors');

// 테스트 설정
export const options = {
  stages: [
    { duration: '30s', target: 50 },   // Ramp up to 50 users
    { duration: '1m', target: 100 },   // Ramp up to 100 users
    { duration: '2m', target: 100 },   // Stay at 100 users
    { duration: '30s', target: 200 },  // Spike to 200 users
    { duration: '1m', target: 200 },   // Stay at 200 users
    { duration: '30s', target: 0 },    // Ramp down to 0 users
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests should be below 500ms
    errors: ['rate<0.1'],              // Error rate should be below 10%
  },
};

const BASE_URL = 'http://localhost:8000'\;

const services = ['api-service', 'auth-service', 'payment-service'];
const levels = ['INFO', 'WARNING', 'ERROR', 'DEBUG'];

export default function () {
  // 랜덤 로그 생성
  const service = services[Math.floor(Math.random() * services.length)];
  const level = levels[Math.floor(Math.random() * levels.length)];
  
  const payload = JSON.stringify({
    level: level,
    service: service,
    message: `Load test message ${Date.now()}`,
    metadata: {
      test: true,
      timestamp: Date.now(),
      user_id: `test_user_${Math.floor(Math.random() * 1000)}`
    }
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  // 단일 로그 전송
  const res = http.post(`${BASE_URL}/api/logs`, payload, params);
  
  // 응답 검증
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  errorRate.add(!success);

  // 10%의 요청은 배치로 전송
  if (Math.random() < 0.1) {
    const batchSize = Math.floor(Math.random() * 50) + 10;
    http.post(`${BASE_URL}/api/logs/batch?count=${batchSize}&service=${service}`);
  }

  sleep(0.1); // 100ms 대기
}

export function handleSummary(data) {
  return {
    'load-test-results.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

function textSummary(data, options) {
  const indent = options.indent || '';
  const enableColors = options.enableColors !== false;
  
  let summary = '\n' + indent + '=== Load Test Summary ===\n\n';
  
  // VUs
  summary += indent + `Virtual Users: ${data.metrics.vus.values.max}\n`;
  
  // Requests
  const reqDuration = data.metrics.http_req_duration;
  summary += indent + `Total Requests: ${data.metrics.http_reqs.values.count}\n`;
  summary += indent + `Request Rate: ${data.metrics.http_reqs.values.rate.toFixed(2)}/s\n`;
  summary += indent + `Avg Duration: ${reqDuration.values.avg.toFixed(2)}ms\n`;
  summary += indent + `P95 Duration: ${reqDuration.values['p(95)'].toFixed(2)}ms\n`;
  
  // Errors
  const errors = data.metrics.errors;
  if (errors) {
    summary += indent + `Error Rate: ${(errors.values.rate * 100).toFixed(2)}%\n`;
  }
  
  return summary;
}
