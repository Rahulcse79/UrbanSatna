-- KYC photos on worker applications (ID document + selfie).
-- Small images (≤1 MB, API-enforced) in PG for this phase; moves to a
-- private S3 bucket behind a StorageProvider trait later (CLAUDE.md §8).
ALTER TABLE worker_applications
    ADD COLUMN kyc_doc bytea,
    ADD COLUMN kyc_doc_mime text,
    ADD COLUMN kyc_selfie bytea,
    ADD COLUMN kyc_selfie_mime text;
