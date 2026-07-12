-- Support chat picks up attachments (images and short videos, ≤10 MB)
-- alongside text. Nullable columns keep every existing message valid;
-- the CHECK enforces "at least body or attachment".
ALTER TABLE support_messages
    ADD COLUMN attachment      bytea,
    ADD COLUMN attachment_mime text;
-- body was NOT NULL by default; loosen it so an attachment-only message
-- is allowed.
ALTER TABLE support_messages ALTER COLUMN body DROP NOT NULL;
ALTER TABLE support_messages
    ADD CONSTRAINT support_messages_content_check
    CHECK (body IS NOT NULL OR attachment IS NOT NULL);
