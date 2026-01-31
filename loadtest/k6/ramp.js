import http from 'k6/http';
import { check, sleep } from 'k6';

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Fetch user IDs in setup phase
export function setup() {
    const res = http.get(`${BASE_URL}/users?limit=200&offset=0`);
    
    if (res.status !== 200) {
        throw new Error(`Failed to fetch users: ${res.status}`);
    }
    
    const users = JSON.parse(res.body).items;
    return { userIds: users.map(u => u.id) };
}

// Ramp test - gradual load increase
export const options = {
    scenarios: {
        ramp: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '2m', target: 200 },  // Ramp up to 200 VUs
                { duration: '2m', target: 200 },  // Stay at 200 VUs
                { duration: '1m', target: 0 },    // Ramp down to 0
            ],
            tags: { test_type: 'ramp' },
        },
    },
    thresholds: {
        http_req_duration: ['p(95)<150', 'p(99)<300'],
        http_req_failed: ['rate<0.05'],
    },
};

export default function(data) {
    const userId = data.userIds[Math.floor(Math.random() * data.userIds.length)];
    const res = http.get(`${BASE_URL}/users/${userId}`);
    
    check(res, {
        'status is 200': (r) => r.status === 200,
        'has user id': (r) => JSON.parse(r.body).id !== undefined,
    });
    
    sleep(0.1);
}
