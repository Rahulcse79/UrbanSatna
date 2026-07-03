-- Catalog (admin-managed data, never code) + booking engine.

CREATE TABLE categories (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL UNIQUE,
    icon       text,                      -- icon key the app maps to a glyph
    sort_order integer NOT NULL DEFAULT 0,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);
CREATE TRIGGER categories_updated_at BEFORE UPDATE ON categories
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE services (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id      uuid NOT NULL REFERENCES categories(id),
    name             text NOT NULL,
    description      text,
    base_price_paise bigint NOT NULL CHECK (base_price_paise > 0),
    duration_min     integer NOT NULL DEFAULT 60,
    is_active        boolean NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    deleted_at       timestamptz
);
CREATE INDEX services_category_id_idx ON services (category_id);
CREATE TRIGGER services_updated_at BEFORE UPDATE ON services
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE bookings (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id  uuid NOT NULL REFERENCES users(id),
    service_id   uuid NOT NULL REFERENCES services(id),
    worker_id    uuid REFERENCES users(id),
    status       text NOT NULL DEFAULT 'pending' CHECK (status IN
                 ('pending','accepted','en_route','in_progress','completed','cancelled')),
    address      text NOT NULL,
    note         text,
    price_paise  bigint NOT NULL CHECK (price_paise > 0),  -- snapshot at booking time
    rating       integer CHECK (rating BETWEEN 1 AND 5),
    review       text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    accepted_at  timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz
);
CREATE INDEX bookings_customer_idx ON bookings (customer_id, status);
CREATE INDEX bookings_worker_idx ON bookings (worker_id, status);
CREATE INDEX bookings_pending_idx ON bookings (created_at) WHERE status = 'pending';
CREATE TRIGGER bookings_updated_at BEFORE UPDATE ON bookings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Launch catalog (mockup categories); admins manage the rest at runtime.
INSERT INTO categories (name, icon, sort_order) VALUES
    ('Electrician',      'electrician', 1),
    ('Plumber',          'plumber',     2),
    ('AC Mechanic',      'ac',          3),
    ('Appliance Repair', 'appliance',   4),
    ('Home Cleaning',    'cleaning',    5),
    ('Carpenter',        'carpenter',   6);

INSERT INTO services (category_id, name, description, base_price_paise, duration_min)
SELECT c.id, s.name, s.description, s.price, s.duration
FROM categories c
JOIN (VALUES
    ('Electrician',      'Fan Installation',        'Ceiling/wall fan install', 29900, 45),
    ('Electrician',      'Wiring Repair',           'Faulty wiring diagnosis & fix', 49900, 90),
    ('Electrician',      'Switchboard Repair',      'Switch/socket replacement', 19900, 30),
    ('Plumber',          'Leaking Pipe Fix',        'Pipe leak repair', 39900, 60),
    ('Plumber',          'Tap Installation',        'Tap/faucet install or replace', 24900, 30),
    ('AC Mechanic',      'AC Service',              'Full AC cleaning & gas check', 59900, 90),
    ('AC Mechanic',      'AC Installation',         'Split AC install', 149900, 120),
    ('Appliance Repair', 'Fridge Repair',           'Refrigerator diagnosis & repair', 49900, 60),
    ('Appliance Repair', 'Washing Machine Repair',  'Washer diagnosis & repair', 44900, 60),
    ('Home Cleaning',    'Full Home Deep Clean',    '2BHK deep cleaning', 249900, 240),
    ('Home Cleaning',    'Bathroom Cleaning',       'Deep bathroom clean', 49900, 60),
    ('Carpenter',        'Furniture Repair',        'Wood furniture fix', 34900, 60),
    ('Carpenter',        'Door Repair',             'Door alignment/lock fix', 29900, 45)
) AS s(cat, name, description, price, duration) ON s.cat = c.name;
