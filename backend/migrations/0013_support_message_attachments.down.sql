-- Reverse of 0013_support_message_attachments.
-- Drop attachment-only rows before restoring the text-required schema so
-- the DROP COLUMN + NOT NULL restore never fails on legitimate data.
DELETE FROM support_messages WHERE body IS NULL;
ALTER TABLE support_messages DROP CONSTRAINT support_messages_content_check;
ALTER TABLE support_messages ALTER COLUMN body SET NOT NULL;
ALTER TABLE support_messages
    DROP COLUMN attachment_mime,
    DROP COLUMN attachment;
