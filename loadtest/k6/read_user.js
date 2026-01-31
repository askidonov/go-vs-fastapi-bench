import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Fetch user IDs in setup phase
export function setup() {
    // Fetch first 200 users to get their IDs
    const res = http.get(`${BASE_URL}/users?limit=200&offset=0`);
    
    if (res.status !== 200) {
        throw new Error(`Failed to fetch users: ${res.status}`);
    }
    
    const users = JSON.parse(res.body).items;
    return { userIds: users.map(u => u.id) };
}

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
        http_req_duration: ['p(95)<100', 'p(99)<200'],
        http_req_failed: ['rate<0.01'],
    },
};

export default function(data) {
    // Randomly select a user ID
    const userId = data.userIds[Math.floor(Math.random() * data.userIds.length)];
    
    // Make request
    const res = http.get(`${BASE_URL}/users/${userId}`);
    
    // Check response
    check(res, {
        'status is 200': (r) => r.status === 200,
        'has user id': (r) => JSON.parse(r.body).id !== undefined,
        'has email': (r) => JSON.parse(r.body).email !== undefined,
    });
    
    sleep(0.1);
}
