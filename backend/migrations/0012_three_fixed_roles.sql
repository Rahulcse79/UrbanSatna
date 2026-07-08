-- Consolidate to exactly three fixed roles: admin, customer, serviceman.
--
-- 1) "worker" is renamed to "serviceman" (same row — every user_roles and
--    role_permissions link keeps working; only the name changes).
-- 2) "super_admin" folds into "admin": admin absorbs its remaining
--    permissions (rbac:manage) and its members, then the role is deleted
--    (role_permissions/user_roles rows cascade).

UPDATE roles
   SET name = 'serviceman', description = 'Provides services'
 WHERE name = 'worker';

-- admin gains every permission super_admin had (i.e. rbac:manage).
INSERT INTO role_permissions (role_id, permission_id)
SELECT a.id, rp.permission_id
  FROM roles a
  JOIN roles sa ON sa.name = 'super_admin'
  JOIN role_permissions rp ON rp.role_id = sa.id
 WHERE a.name = 'admin'
ON CONFLICT DO NOTHING;

-- super_admin members become plain admins.
INSERT INTO user_roles (user_id, role_id)
SELECT ur.user_id, a.id
  FROM user_roles ur
  JOIN roles sa ON sa.id = ur.role_id AND sa.name = 'super_admin'
  JOIN roles a ON a.name = 'admin'
ON CONFLICT DO NOTHING;

DELETE FROM roles WHERE name = 'super_admin';
