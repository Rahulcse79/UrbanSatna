-- Reverse of 0007_kyc_documents.
ALTER TABLE worker_applications
    DROP COLUMN kyc_selfie_mime,
    DROP COLUMN kyc_selfie,
    DROP COLUMN kyc_doc_mime,
    DROP COLUMN kyc_doc;
