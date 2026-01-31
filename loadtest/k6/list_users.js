import http from 'k6/http';
import { check, sleep } from 'k6';

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Test scenarios
export const options = {
    scenarios: {
        smoke: {
            executor: 'constant-vus',
            vus: 10,
            duration: '30s',
            tags: { test_type: 'smoke' },
        },
    },
    thresholds: {
        http_req_duration: ['p(95)<150', 'p(99)<300'],
        http_req_failed: ['rate<0.01'],
    },
};

export default function() {
    // Random offset between 0 and 9950 (to ensure we can fetch 50 items)
    const offset = Math.floor(Math.random() * 9950);
    const limit = 50;
    
    // Make request
    const res = http.get(`${BASE_URL}/users?limit=${limit}&offset=${offset}`);
    
    // Check response
    check(res, {
        'status is 200': (r) => r.status === 200,
        'has items': (r) => JSON.parse(r.body).items.length > 0,
        'has total': (r) => JSON.parse(r.body).total > 0,
        'limit matches': (r) => JSON.parse(r.body).limit === limit,
        'offset matches': (r) => JSON.parse(r.body).offset === offset,
    });
    
    sleep(0.1);
}
