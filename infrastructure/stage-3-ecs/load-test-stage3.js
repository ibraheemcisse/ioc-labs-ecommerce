// Stage 3 ECS Fargate Load Testing Script
// Tests auto-scaling, performance limits, and breaking points
// Run with: k6 run load-test-stage3.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const successfulRequests = new Counter('successful_requests');
const responseTime = new Trend('response_time');

// Configuration
const BASE_URL = 'http://ioc-labs-alb-fargate-475422843.us-east-1.elb.amazonaws.com';

// Test scenarios
export const options = {
  scenarios: {
    // Scenario 1: Baseline - Current capacity test
    baseline: {
      executor: 'constant-vus',
      vus: 10,
      duration: '2m',
      startTime: '0s',
      tags: { test_type: 'baseline' },
    },
    
    // Scenario 2: Ramp up - Test scaling behavior
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: '2m', target: 50 },   // Gradual increase
        { duration: '3m', target: 100 },  // More pressure
        { duration: '2m', target: 200 },  // Heavy load
        { duration: '3m', target: 200 },  // Sustained heavy load
        { duration: '2m', target: 0 },    // Ramp down
      ],
      startTime: '2m',
      tags: { test_type: 'ramp_up' },
    },
    
    // Scenario 3: Spike test - Sudden traffic surge
    spike: {
      executor: 'ramping-vus',
      stages: [
        { duration: '10s', target: 500 },  // Sudden spike
        { duration: '1m', target: 500 },   // Hold
        { duration: '10s', target: 0 },    // Drop
      ],
      startTime: '14m',
      tags: { test_type: 'spike' },
    },
    
    // Scenario 4: Stress test - Find breaking point
    stress: {
      executor: 'ramping-vus',
      stages: [
        { duration: '2m', target: 100 },
        { duration: '2m', target: 300 },
        { duration: '2m', target: 500 },
        { duration: '2m', target: 700 },
        { duration: '2m', target: 1000 }, // Find the limit
        { duration: '3m', target: 1000 }, // Sustain max load
        { duration: '2m', target: 0 },
      ],
      startTime: '16m',
      tags: { test_type: 'stress' },
    },
  },
  
  thresholds: {
    // Success criteria
    'http_req_duration': ['p(95)<500', 'p(99)<1000'], // 95% < 500ms, 99% < 1s
    'http_req_failed': ['rate<0.05'],                 // Error rate < 5%
    'errors': ['rate<0.05'],
    'http_reqs': ['rate>100'],                        // Minimum 100 req/s
  },
};

// Test data
const products = Array.from({ length: 50 }, (_, i) => i + 1);

// Main test function
export default function() {
  const testType = __ENV.TEST_TYPE || 'full';
  
  // Randomize endpoints to simulate real traffic
  const endpoint = selectEndpoint();
  
  const response = http.get(`${BASE_URL}${endpoint}`, {
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'k6-load-test',
    },
    tags: { endpoint: endpoint },
  });
  
  // Track metrics
  responseTime.add(response.timings.duration);
  
  // Validate response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'response time < 1000ms': (r) => r.timings.duration < 1000,
    'has valid JSON': (r) => {
      try {
        JSON.parse(r.body);
        return true;
      } catch {
        return false;
      }
    },
    'success field is true': (r) => {
      try {
        const data = JSON.parse(r.body);
        return data.success === true;
      } catch {
        return false;
      }
    },
  });
  
  if (success) {
    successfulRequests.add(1);
  } else {
    errorRate.add(1);
    console.error(`Failed request: ${endpoint} - Status: ${response.status} - Duration: ${response.timings.duration}ms`);
  }
  
  // Realistic user behavior - random think time
  sleep(Math.random() * 2 + 0.5); // 0.5-2.5 seconds between requests
}

// Select random endpoint to simulate real traffic patterns
function selectEndpoint() {
  const rand = Math.random();
  
  // Traffic distribution based on typical e-commerce patterns
  if (rand < 0.4) {
    // 40% - Browse products
    return '/api/products';
  } else if (rand < 0.7) {
    // 30% - View specific product
    const productId = products[Math.floor(Math.random() * products.length)];
    return `/api/products/${productId}`;
  } else if (rand < 0.85) {
    // 15% - Search
    const queries = ['electronics', 'clothing', 'home'];
    const query = queries[Math.floor(Math.random() * queries.length)];
    return `/api/products/search?q=${query}`;
  } else {
    // 15% - Health check
    return '/api/products'; // Using products as health check
  }
}

// Setup function - runs once before test
export function setup() {
  console.log('Starting load test against:', BASE_URL);
  console.log('Testing ECS Fargate auto-scaling and performance limits');
  
  // Verify endpoint is reachable
  const response = http.get(`${BASE_URL}/api/products`);
  
  if (response.status !== 200) {
    throw new Error(`Setup failed: ${BASE_URL}/api/products returned ${response.status}`);
  }
  
  console.log('Baseline check passed - starting load test');
  
  return {
    startTime: new Date().toISOString(),
    baseUrl: BASE_URL,
  };
}

// Teardown function - runs once after test
export function teardown(data) {
  console.log('Load test completed');
  console.log('Start time:', data.startTime);
  console.log('End time:', new Date().toISOString());
  console.log('Base URL:', data.baseUrl);
}

// Handle iteration
export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'summary.json': JSON.stringify(data),
    'summary.html': htmlReport(data),
  };
}

// Text summary helper
function textSummary(data, options) {
  const indent = options.indent || '';
  const enableColors = options.enableColors !== false;
  
  let output = '\n';
  output += `${indent}Load Test Summary\n`;
  output += `${indent}================\n\n`;
  
  // Request stats
  output += `${indent}Requests:\n`;
  output += `${indent}  Total: ${data.metrics.http_reqs.values.count}\n`;
  output += `${indent}  Rate: ${data.metrics.http_reqs.values.rate.toFixed(2)} req/s\n`;
  output += `${indent}  Failed: ${(data.metrics.http_req_failed.values.rate * 100).toFixed(2)}%\n\n`;
  
  // Response time stats
  output += `${indent}Response Time:\n`;
  output += `${indent}  Min: ${data.metrics.http_req_duration.values.min.toFixed(2)}ms\n`;
  output += `${indent}  Avg: ${data.metrics.http_req_duration.values.avg.toFixed(2)}ms\n`;
  output += `${indent}  P95: ${data.metrics.http_req_duration.values['p(95)'].toFixed(2)}ms\n`;
  output += `${indent}  P99: ${data.metrics.http_req_duration.values['p(99)'].toFixed(2)}ms\n`;
  output += `${indent}  Max: ${data.metrics.http_req_duration.values.max.toFixed(2)}ms\n\n`;
  
  // Virtual users
  output += `${indent}Virtual Users:\n`;
  output += `${indent}  Max: ${data.metrics.vus_max.values.value}\n`;
  output += `${indent}  Avg: ${data.metrics.vus.values.value.toFixed(2)}\n\n`;
  
  // Thresholds
  output += `${indent}Thresholds:\n`;
  Object.keys(data.thresholds || {}).forEach(threshold => {
    const passed = data.thresholds[threshold].ok ? '✓' : '✗';
    output += `${indent}  ${passed} ${threshold}\n`;
  });
  
  return output;
}

// Simple HTML report generator
function htmlReport(data) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Load Test Report - Stage 3</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
    .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    h1 { color: #333; border-bottom: 3px solid #4CAF50; padding-bottom: 10px; }
    .metric { margin: 20px 0; padding: 15px; background: #f9f9f9; border-left: 4px solid #4CAF50; }
    .metric h3 { margin: 0 0 10px 0; color: #555; }
    .value { font-size: 24px; font-weight: bold; color: #333; }
    .label { font-size: 14px; color: #777; margin-top: 5px; }
    .threshold { padding: 10px; margin: 5px 0; border-radius: 4px; }
    .pass { background: #d4edda; color: #155724; }
    .fail { background: #f8d7da; color: #721c24; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Load Test Report - Stage 3 ECS Fargate</h1>
    <p><strong>Date:</strong> ${new Date().toISOString()}</p>
    
    <div class="metric">
      <h3>Total Requests</h3>
      <div class="value">${data.metrics.http_reqs.values.count}</div>
      <div class="label">${data.metrics.http_reqs.values.rate.toFixed(2)} req/s</div>
    </div>
    
    <div class="metric">
      <h3>Response Time (P95)</h3>
      <div class="value">${data.metrics.http_req_duration.values['p(95)'].toFixed(2)}ms</div>
      <div class="label">95th percentile</div>
    </div>
    
    <div class="metric">
      <h3>Error Rate</h3>
      <div class="value">${(data.metrics.http_req_failed.values.rate * 100).toFixed(2)}%</div>
      <div class="label">Failed requests</div>
    </div>
    
    <h2>Thresholds</h2>
    ${Object.keys(data.thresholds || {}).map(threshold => `
      <div class="threshold ${data.thresholds[threshold].ok ? 'pass' : 'fail'}">
        ${data.thresholds[threshold].ok ? '✓' : '✗'} ${threshold}
      </div>
    `).join('')}
  </div>
</body>
</html>
  `;
}
