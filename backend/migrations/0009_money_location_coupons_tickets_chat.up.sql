-- Money, location, coupons, tickets, chat (control plane v3).

-- Customer-shared GPS pin: precise navigation for the worker.
ALTER TABLE bookings ADD COLUMN lat double precision;
ALTER TABLE bookings ADD COLUMN lng double precision;
-- Coupon snapshot: price_paise is the FINAL charged amount; the discount
-- and code are kept for the record/invoice.
ALTER TABLE bookings ADD COLUMN coupon_code text;
ALTER TABLE bookings ADD COLUMN discount_paise bigint NOT NULL DEFAULT 0;

-- Coupons: percent OR flat, one redemption per user forever.
CREATE TABLE coupons (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code           text NOT NULL UNIQUE,          -- stored uppercase
    percent_off    integer CHECK (percent_off BETWEEN 1 AND 90),
    flat_off_paise bigint CHECK (flat_off_paise > 0),
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CHECK ((percent_off IS NULL) <> (flat_off_paise IS NULL))
);
CREATE TRIGGER coupons_updated_at BEFORE UPDATE ON coupons
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- The primary key IS the business rule: one use per user, ever.
-- Admin deactivating/reactivating a coupon never resets redemptions.
CREATE TABLE coupon_redemptions (
    coupon_id  uuid NOT NULL REFERENCES coupons(id),
    user_id    uuid NOT NULL REFERENCES users(id),
    booking_id uuid NOT NULL REFERENCES bookings(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (coupon_id, user_id)
);

-- Support tickets: customer raises, admin resolves.
CREATE TABLE tickets (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users(id),
    booking_id  uuid REFERENCES bookings(id),
    subject     text NOT NULL,
    message     text NOT NULL,
    status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved')),
    resolution  text,
    resolved_by uuid REFERENCES users(id),
    resolved_at timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tickets_status_idx ON tickets (status, created_at);
CREATE INDEX tickets_user_idx ON tickets (user_id, created_at);
CREATE TRIGGER tickets_updated_at BEFORE UPDATE ON tickets
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Booking chat between the customer and the assigned worker.
-- Attachments (PNG/JPG/MP4 ≤ 15 MB) in PG for this phase; S3 later.
CREATE TABLE booking_messages (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id      uuid NOT NULL REFERENCES bookings(id),
    sender_id       uuid NOT NULL REFERENCES users(id),
    body            text,
    attachment      bytea,
    attachment_mime text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CHECK (body IS NOT NULL OR attachment IS NOT NULL)
);
CREATE INDEX booking_messages_booking_idx ON booking_messages (booking_id, created_at);
