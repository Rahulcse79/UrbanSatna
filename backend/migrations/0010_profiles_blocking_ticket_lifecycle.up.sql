-- Profile completion, T&C acceptance, user blocking, ticket close/reopen.

ALTER TABLE users
    ADD COLUMN address text,
    ADD COLUMN state text,
    ADD COLUMN city text,
    ADD COLUMN pincode text,
    ADD COLUMN terms_accepted_at timestamptz,
    ADD COLUMN blocked_at timestamptz,
    ADD COLUMN block_reason text;

-- closed = permanently closed by admin; users can reopen 'resolved' only.
ALTER TABLE tickets DROP CONSTRAINT tickets_status_check;
ALTER TABLE tickets ADD CONSTRAINT tickets_status_check
    CHECK (status IN ('open','resolved','closed'));

INSERT INTO permissions (code, description) VALUES
    ('users:manage:any', 'Block/unblock users, view user list');
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name IN ('admin','super_admin') AND p.code = 'users:manage:any';
