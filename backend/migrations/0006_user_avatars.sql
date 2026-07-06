-- Profile pictures: small (≤1 MB, enforced in the API) so DB storage is
-- fine for this phase; moves to S3 behind a StorageProvider trait later.
ALTER TABLE users ADD COLUMN avatar bytea;
ALTER TABLE users ADD COLUMN avatar_mime text;
