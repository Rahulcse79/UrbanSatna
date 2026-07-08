-- Reverse of 0004_app_settings. Deleting the permission cascades its
-- role_permissions grants.
DELETE FROM permissions WHERE code = 'settings:manage';
DROP TABLE app_settings;
