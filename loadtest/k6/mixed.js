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

// Test scenarios - mixed workload
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

export default function(data) {
    // 70% read single user, 30% list users
    const rand = Math.random();
    
    if (rand < 0.7) {
        // Read single user
        const userId = data.userIds[Math.floor(Math.random() * data.userIds.length)];
        const res = http.get(`${BASE_URL}/users/${userId}`);
        
        check(res, {
            'read: status is 200': (r) => r.status === 200,
            'read: has user id': (r) => JSON.parse(r.body).id !== undefined,
        });
    } else {
        // List users
        const offset = Math.floor(Math.random() * 9950);
        const limit = 50;
        const res = http.get(`${BASE_URL}/users?limit=${limit}&offset=${offset}`);
        
        check(res, {
            'list: status is 200': (r) => r.status === 200,
            'list: has items': (r) => JSON.parse(r.body).items.length > 0,
        });
    }
    
    sleep(0.1);
}
