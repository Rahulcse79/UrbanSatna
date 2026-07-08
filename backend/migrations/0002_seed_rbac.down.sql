-- Reverse of 0002_seed_rbac. Deletes exactly what the seed inserted;
-- role/permission deletes cascade through role_permissions and user_roles.
DELETE FROM roles WHERE name IN ('customer', 'worker', 'admin', 'super_admin');
DELETE FROM permissions WHERE code IN (
    'users:read:own', 'users:update:own', 'bookings:create', 'bookings:read:own',
    'bookings:read:any', 'bookings:manage:any', 'workers:verify', 'catalog:manage',
    'rbac:manage', 'audit:read');
-- users.city_id has a plain FK (no cascade): detach before deleting the city.
UPDATE users SET city_id = NULL
 WHERE city_id IN (SELECT id FROM cities WHERE name = 'Satna' AND state = 'Madhya Pradesh');
DELETE FROM cities WHERE name = 'Satna' AND state = 'Madhya Pradesh';
