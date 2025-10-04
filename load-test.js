import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '2m', target: 10 },   // Baseline
    { duration: '2m', target: 50 },   // Medium
    { duration: '2m', target: 100 },  // High
    { duration: '2m', target: 200 },  // Stress
    { duration: '1m', target: 0 },    // Ramp down
  ],
};

export default function () {
  const res = http.get('http://3.92.52.46/api/products');
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}
