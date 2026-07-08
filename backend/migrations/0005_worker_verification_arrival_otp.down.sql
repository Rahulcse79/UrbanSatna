-- Reverse of 0005_worker_verification_arrival_otp.
-- 'arrived' leaves the status set: map such rows back to the closest
-- surviving predecessor state before narrowing the constraint.
ALTER TABLE bookings DROP CONSTRAINT bookings_status_check;
UPDATE bookings SET status = 'en_route' WHERE status = 'arrived';
ALTER TABLE bookings ADD CONSTRAINT bookings_status_check CHECK (status IN
    ('pending','accepted','en_route','in_progress','completed','cancelled'));
ALTER TABLE bookings DROP COLUMN arrived_at;
ALTER TABLE bookings DROP COLUMN arrival_otp;
DROP TABLE worker_applications;
