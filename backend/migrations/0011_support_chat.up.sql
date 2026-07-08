-- Live support: one thread per user with the admin/support team.
CREATE TABLE support_messages (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id),   -- thread owner
    sender_id  uuid NOT NULL REFERENCES users(id),   -- user or staff
    body       text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX support_messages_user_idx ON support_messages (user_id, created_at);
