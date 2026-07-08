-- Reverse of 0009_money_location_coupons_tickets_chat.
-- Tables that reference bookings drop first, then the added columns.
DROP TABLE booking_messages;
DROP TABLE tickets;
DROP TABLE coupon_redemptions;
DROP TABLE coupons;
ALTER TABLE bookings
    DROP COLUMN discount_paise,
    DROP COLUMN coupon_code,
    DROP COLUMN lng,
    DROP COLUMN lat;
