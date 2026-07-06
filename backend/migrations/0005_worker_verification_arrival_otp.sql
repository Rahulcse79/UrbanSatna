-- M2: verified-only workers + arrival OTP handshake (PRODUCT.md §12.2/§12.3).
-- Workers apply; only an admin decision grants the worker role.

CREATE TABLE worker_applications (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id),
    status     text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','approved','rejected')),
    skills     text,
    experience text,
    note       text,                          -- admin's decision note
    decided_by uuid REFERENCES users(id),
    decided_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
-- one live application per user
CREATE UNIQUE INDEX worker_applications_pending_uidx
    ON worker_applications (user_id) WHERE status = 'pending';
CREATE INDEX worker_applications_status_idx ON worker_applications (status, created_at);
CREATE TRIGGER worker_applications_updated_at BEFORE UPDATE ON worker_applications
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Grandfather users who became workers via the test-phase toggle so they
-- keep working; every future worker goes through the queue.
INSERT INTO worker_applications (user_id, status, decided_at, note)
SELECT ur.user_id, 'approved', now(), 'grandfathered: pre-verification worker'
FROM user_roles ur
JOIN roles r ON r.id = ur.role_id
WHERE r.name = 'worker';

-- Arrival OTP: customer shares it at the door; work can't start without it.
ALTER TABLE bookings ADD COLUMN arrival_otp text;
ALTER TABLE bookings ADD COLUMN arrived_at timestamptz;
ALTER TABLE bookings DROP CONSTRAINT bookings_status_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_status_check CHECK (status IN
    ('pending','accepted','en_route','arrived','in_progress','completed','cancelled'));

-- Backfill active bookings so in-flight jobs can still advance.
UPDATE bookings
   SET arrival_otp = lpad(floor(random() * 10000)::int::text, 4, '0')
 WHERE status NOT IN ('completed','cancelled') AND arrival_otp IS NULL;
