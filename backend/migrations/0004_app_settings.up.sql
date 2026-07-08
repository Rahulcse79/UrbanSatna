-- Runtime app settings, toggled by admins without redeploys.

CREATE TABLE app_settings (
    key        text PRIMARY KEY,
    value      jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Default: users may change the server URL in the app (fail-open —
-- code also defaults to true when the row is missing).
INSERT INTO app_settings (key, value) VALUES ('allow_server_url_change', 'true'::jsonb);

INSERT INTO permissions (code, description)
VALUES ('settings:manage', 'Manage runtime app settings');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name IN ('admin', 'super_admin') AND p.code = 'settings:manage';
