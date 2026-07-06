-- Cancellation reasons: picked by the customer, visible to support/ops.
ALTER TABLE bookings ADD COLUMN cancel_reason text;
