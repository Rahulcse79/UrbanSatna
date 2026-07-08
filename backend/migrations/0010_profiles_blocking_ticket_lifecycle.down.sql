-- Reverse of 0010_profiles_blocking_ticket_lifecycle.
-- Deleting the permission cascades its role_permissions grants.
DELETE FROM permissions WHERE code = 'users:manage:any';

-- 'closed' leaves the status set: fold such tickets back into 'resolved'
-- before narrowing the constraint.
ALTER TABLE tickets DROP CONSTRAINT tickets_status_check;
UPDATE tickets SET status = 'resolved' WHERE status = 'closed';
ALTER TABLE tickets ADD CONSTRAINT tickets_status_check
    CHECK (status IN ('open','resolved'));

ALTER TABLE users
    DROP COLUMN block_reason,
    DROP COLUMN blocked_at,
    DROP COLUMN terms_accepted_at,
    DROP COLUMN pincode,
    DROP COLUMN city,
    DROP COLUMN state,
    DROP COLUMN address;
