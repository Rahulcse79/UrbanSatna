-- Reverse of 0001_foundations. Dev-only (docs/MIGRATIONS.md): production
-- never runs revert. Drops in reverse dependency order; triggers drop with
-- their tables.
DROP TABLE audit_logs;
DROP TABLE sessions;
DROP TABLE user_roles;
DROP TABLE role_permissions;
DROP TABLE permissions;
DROP TABLE roles;
DROP TABLE users;
DROP TABLE cities;
DROP FUNCTION set_updated_at();
