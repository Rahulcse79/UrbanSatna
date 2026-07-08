-- Phase 0 foundations: identity, RBAC, sessions, cities, audit trail.
-- Conventions (CLAUDE.md §6): UUID PKs, created_at/updated_at everywhere,
-- soft delete via deleted_at on user-facing data, forward-only migrations.

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------- cities
CREATE TABLE cities (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL,
    state      text NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    UNIQUE (name, state)
);
CREATE TRIGGER cities_updated_at BEFORE UPDATE ON cities
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ----------------------------------------------------------------- users
CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone         text NOT NULL UNIQUE,          -- E.164, e.g. +919876543210
    email         text UNIQUE,
    full_name     text,
    password_hash text,                          -- nullable: OTP-first auth
    city_id       uuid REFERENCES cities(id),
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    deleted_at    timestamptz
);
CREATE INDEX users_city_id_idx ON users (city_id);
CREATE TRIGGER users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ------------------------------------------------------------------ rbac
CREATE TABLE roles (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL UNIQUE,            -- customer | worker | admin | super_admin
    description text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE permissions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text NOT NULL UNIQUE,            -- e.g. bookings:read:own
    description text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE role_permissions (
    role_id       uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_roles (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

-- -------------------------------------------------------------- sessions
-- One row per logged-in device; refresh tokens are stored hashed and
-- rotated on every use. Revoking a row logs that device out.
CREATE TABLE sessions (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash text NOT NULL,
    device_id          text,
    device_name        text,
    user_agent         text,
    ip                 inet,
    expires_at         timestamptz NOT NULL,
    revoked_at         timestamptz,
    last_used_at       timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_id_idx ON sessions (user_id);
CREATE UNIQUE INDEX sessions_refresh_token_hash_idx ON sessions (refresh_token_hash);

-- ------------------------------------------------------------ audit_logs
-- Append-only. Every state-changing action writes one row (CLAUDE.md §1.3).
CREATE TABLE audit_logs (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id    uuid REFERENCES users(id),
    actor_type  text NOT NULL DEFAULT 'system', -- system | customer | worker | admin
    action      text NOT NULL,                  -- e.g. booking.state_changed
    entity_type text,
    entity_id   uuid,
    before      jsonb,
    after       jsonb,
    request_id  text,
    ip          inet,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_entity_idx ON audit_logs (entity_type, entity_id);
CREATE INDEX audit_logs_actor_idx ON audit_logs (actor_id);
CREATE INDEX audit_logs_created_at_idx ON audit_logs (created_at);
