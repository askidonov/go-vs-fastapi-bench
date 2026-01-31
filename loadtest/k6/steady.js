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

// Steady load test
export const options = {
    scenarios: {
        steady: {
            executor: 'constant-vus',
            vus: 100,
            duration: '2m',
            tags: { test_type: 'steady' },
        },
    },
    thresholds: {
        http_req_duration: ['p(95)<100', 'p(99)<200'],
        http_req_failed: ['rate<0.01'],
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
