-- Seed 10,000 users using generate_series
INSERT INTO users (email, full_name, age, country_code, is_active, created_at)
SELECT
    'user' || n || '@example.com' AS email,
    'User ' || n AS full_name,
    (20 + (n % 50)) AS age,  -- Age between 20 and 69
    CASE (n % 10)
        WHEN 0 THEN 'US'
        WHEN 1 THEN 'UK'
        WHEN 2 THEN 'CA'
        WHEN 3 THEN 'DE'
        WHEN 4 THEN 'FR'
        WHEN 5 THEN 'JP'
        WHEN 6 THEN 'AU'
        WHEN 7 THEN 'BR'
        WHEN 8 THEN 'IN'
        ELSE 'CN'
    END AS country_code,
    (n % 10 != 0) AS is_active,  -- ~90% active users
    now() - (n || ' seconds')::interval AS created_at
FROM generate_series(1, 10000) AS n
ON CONFLICT (email) DO NOTHING;

-- Verify the count
DO $$
DECLARE
    user_count INT;
BEGIN
    SELECT COUNT(*) INTO user_count FROM users;
    RAISE NOTICE 'Seeded % users', user_count;
END $$;
