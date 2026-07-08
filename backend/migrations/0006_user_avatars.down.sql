-- Reverse of 0006_user_avatars.
ALTER TABLE users DROP COLUMN avatar_mime;
ALTER TABLE users DROP COLUMN avatar;
