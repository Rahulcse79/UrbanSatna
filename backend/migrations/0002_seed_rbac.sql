-- Seed baseline roles, permissions, and the launch city.
-- Roles and permissions are data (CLAUDE.md §1.4): production admins can
-- add more at runtime; this seed is only the minimum the system assumes.

INSERT INTO roles (name, description) VALUES
    ('customer',    'Books services'),
    ('worker',      'Provides services'),
    ('admin',       'Operations team'),
    ('super_admin', 'Full platform control');

INSERT INTO permissions (code, description) VALUES
    ('users:read:own',      'Read own profile'),
    ('users:update:own',    'Update own profile'),
    ('bookings:create',     'Create a booking'),
    ('bookings:read:own',   'Read own bookings'),
    ('bookings:read:any',   'Read any booking'),
    ('bookings:manage:any', 'Cancel/reassign/refund any booking'),
    ('workers:verify',      'Approve or reject worker KYC'),
    ('catalog:manage',      'Manage categories, services, pricing'),
    ('rbac:manage',         'Manage roles and permissions'),
    ('audit:read',          'Read audit logs');

-- customer
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'customer'
  AND p.code IN ('users:read:own', 'users:update:own',
                 'bookings:create', 'bookings:read:own');

-- worker
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'worker'
  AND p.code IN ('users:read:own', 'users:update:own', 'bookings:read:own');

-- admin: everything except rbac:manage
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'admin' AND p.code <> 'rbac:manage';

-- super_admin: everything
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'super_admin';

INSERT INTO cities (name, state) VALUES ('Satna', 'Madhya Pradesh');
