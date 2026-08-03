BEGIN;

CREATE TABLE IF NOT EXISTS robot_photos (
    id UUID PRIMARY KEY,
    robot_id BIGINT NOT NULL REFERENCES robots(id),
    object_key VARCHAR(500) NOT NULL UNIQUE,
    upload_status VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    mime_type VARCHAR(100) NOT NULL,
    expected_size_bytes BIGINT NOT NULL,
    actual_size_bytes BIGINT,
    captured_at TIMESTAMPTZ NOT NULL,
    upload_expires_at TIMESTAMPTZ NOT NULL,
    uploaded_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT robot_photos_status_check
        CHECK (upload_status IN ('PENDING', 'UPLOADED', 'EXPIRED')),
    CONSTRAINT robot_photos_expected_size_check
        CHECK (expected_size_bytes BETWEEN 1 AND 10485760),
    CONSTRAINT robot_photos_actual_size_check
        CHECK (actual_size_bytes IS NULL OR actual_size_bytes >= 0)
);

CREATE INDEX IF NOT EXISTS idx_robot_photos_robot_created
    ON robot_photos (robot_id, created_at DESC);

COMMIT;
