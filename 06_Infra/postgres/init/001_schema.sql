BEGIN;

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255),
    nickname VARCHAR(100) NOT NULL UNIQUE,
    phone_number VARCHAR(20) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ
);

CREATE TABLE social_accounts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    provider VARCHAR(20) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_social_account_provider_user
        UNIQUE (provider, provider_user_id)
);

CREATE INDEX idx_social_accounts_user_id
    ON social_accounts(user_id);

CREATE TABLE social_signup_tickets (
    id BIGSERIAL PRIMARY KEY,
    token_hash VARCHAR(64) NOT NULL UNIQUE,
    provider VARCHAR(20) NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    suggested_nickname VARCHAR(100),
    device_id VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE auth_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    device_id VARCHAR(255) NOT NULL,
    refresh_token_hash VARCHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_auth_sessions_user_device
    ON auth_sessions(user_id, device_id);

CREATE TABLE auth_verifications (
    id BIGSERIAL PRIMARY KEY,
    phone_number VARCHAR(20) NOT NULL,
    purpose VARCHAR(30) NOT NULL,
    code_hash VARCHAR(255) NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    token_hash VARCHAR(64) UNIQUE,
    token_expires_at TIMESTAMPTZ,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE pets (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    name VARCHAR(100) NOT NULL,
    profile_image_key VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_pets_user_id ON pets(user_id);

CREATE TABLE pet_affinity_states (
    pet_id BIGINT PRIMARY KEY REFERENCES pets(id),
    affinity_score INTEGER NOT NULL DEFAULT 0,
    affinity_level INTEGER NOT NULL DEFAULT 1,
    mood VARCHAR(30) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE robots (
    id BIGSERIAL PRIMARY KEY,
    serial_number VARCHAR(100) NOT NULL UNIQUE,
    model_name VARCHAR(100) NOT NULL,
    firmware_version VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE robot_credentials (
    robot_id BIGINT PRIMARY KEY REFERENCES robots(id),
    device_token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMPTZ,
    rotated_at TIMESTAMPTZ
);

CREATE TABLE robot_pairings (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    pet_id BIGINT NOT NULL REFERENCES pets(id),
    robot_id BIGINT NOT NULL REFERENCES robots(id),
    paired_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    unpaired_at TIMESTAMPTZ
);

CREATE INDEX idx_robot_pairings_user_id ON robot_pairings(user_id);
CREATE INDEX idx_robot_pairings_pet_id ON robot_pairings(pet_id);
CREATE INDEX idx_robot_pairings_robot_id ON robot_pairings(robot_id);

CREATE TABLE robot_current_states (
    robot_id BIGINT PRIMARY KEY REFERENCES robots(id),
    online BOOLEAN NOT NULL DEFAULT FALSE,
    mode VARCHAR(30) NOT NULL,
    battery_level INTEGER NOT NULL DEFAULT 0,
    docked BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_robot_battery_level
        CHECK (battery_level BETWEEN 0 AND 100)
);

CREATE TABLE walk_proposals (
    id BIGSERIAL PRIMARY KEY,
    robot_pairing_id BIGINT NOT NULL REFERENCES robot_pairings(id),
    message VARCHAR(500) NOT NULL,
    status VARCHAR(30) NOT NULL,
    proposed_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    responded_at TIMESTAMPTZ
);

CREATE INDEX idx_walk_proposals_pairing
    ON walk_proposals(robot_pairing_id);

CREATE TABLE walks (
    id BIGSERIAL PRIMARY KEY,
    robot_pairing_id BIGINT NOT NULL REFERENCES robot_pairings(id),
    proposal_id BIGINT UNIQUE REFERENCES walk_proposals(id),
    status VARCHAR(30) NOT NULL,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    distance_meters NUMERIC(10, 2),
    duration_seconds INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_walk_distance_nonnegative
        CHECK (distance_meters IS NULL OR distance_meters >= 0),
    CONSTRAINT chk_walk_duration_nonnegative
        CHECK (duration_seconds IS NULL OR duration_seconds >= 0)
);

CREATE INDEX idx_walks_pairing ON walks(robot_pairing_id);

CREATE TABLE walk_locations (
    id BIGSERIAL PRIMARY KEY,
    walk_id BIGINT NOT NULL REFERENCES walks(id) ON DELETE CASCADE,
    sequence_no INTEGER NOT NULL,
    latitude NUMERIC(10, 7) NOT NULL,
    longitude NUMERIC(10, 7) NOT NULL,
    accuracy_meters NUMERIC(8, 2),
    recorded_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT uk_walk_location_sequence UNIQUE (walk_id, sequence_no),
    CONSTRAINT chk_walk_location_latitude
        CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_walk_location_longitude
        CHECK (longitude BETWEEN -180 AND 180)
);

CREATE INDEX idx_walk_locations_walk_recorded
    ON walk_locations(walk_id, recorded_at);

CREATE TABLE walk_photos (
    id BIGSERIAL PRIMARY KEY,
    walk_id BIGINT NOT NULL REFERENCES walks(id) ON DELETE CASCADE,
    walk_location_id BIGINT REFERENCES walk_locations(id),
    sequence_no INTEGER NOT NULL,
    storage_provider VARCHAR(30) NOT NULL,
    object_key VARCHAR(500) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT,
    checksum VARCHAR(128),
    captured_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_walk_photo_sequence UNIQUE (walk_id, sequence_no),
    CONSTRAINT chk_walk_photo_size_nonnegative
        CHECK (file_size_bytes IS NULL OR file_size_bytes >= 0)
);

CREATE INDEX idx_walk_photos_walk_id ON walk_photos(walk_id);

CREATE TABLE photo_analyses (
    id BIGSERIAL PRIMARY KEY,
    photo_id BIGINT NOT NULL UNIQUE REFERENCES walk_photos(id) ON DELETE CASCADE,
    processing_status VARCHAR(30) NOT NULL,
    caption TEXT,
    model_name VARCHAR(100),
    prompt_version VARCHAR(50),
    retry_count INTEGER NOT NULL DEFAULT 0,
    error_code VARCHAR(100),
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_photo_analysis_retry_nonnegative
        CHECK (retry_count >= 0)
);

CREATE TABLE push_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    device_id VARCHAR(255) NOT NULL,
    platform VARCHAR(20) NOT NULL,
    token VARCHAR(500) NOT NULL UNIQUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_push_token_user_device UNIQUE (user_id, device_id)
);

CREATE TABLE notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id),
    notification_type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body VARCHAR(1000) NOT NULL,
    data JSONB,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_notifications_user_created
    ON notifications(user_id, created_at DESC);

COMMIT;
