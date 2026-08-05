BEGIN;

ALTER TABLE robots
    ADD COLUMN IF NOT EXISTS owner_user_id BIGINT,
    ADD COLUMN IF NOT EXISTS ownership_claimed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE robots
SET updated_at = COALESCE(updated_at, created_at, CURRENT_TIMESTAMP)
WHERE updated_at IS NULL;

ALTER TABLE robots
    ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'robots_owner_user_id_fkey'
    ) THEN
        ALTER TABLE robots
            ADD CONSTRAINT robots_owner_user_id_fkey
            FOREIGN KEY (owner_user_id) REFERENCES users(id);
    END IF;
END
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'robot_pairings'
          AND column_name = 'user_id'
    ) THEN
        EXECUTE '
            UPDATE robots r
            SET owner_user_id = rp.user_id,
                ownership_claimed_at = rp.paired_at
            FROM robot_pairings rp
            WHERE rp.robot_id = r.id
              AND rp.unpaired_at IS NULL
              AND r.owner_user_id IS NULL
        ';

        EXECUTE '
            ALTER TABLE robot_pairings
            ALTER COLUMN user_id DROP NOT NULL
        ';
    END IF;
END
$$;

UPDATE robots
SET ownership_claimed_at = NULL
WHERE owner_user_id IS NULL
  AND ownership_claimed_at IS NOT NULL;

UPDATE robots
SET ownership_claimed_at = CURRENT_TIMESTAMP
WHERE owner_user_id IS NOT NULL
  AND ownership_claimed_at IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'robots_ownership_claim_check'
    ) THEN
        ALTER TABLE robots
            ADD CONSTRAINT robots_ownership_claim_check
            CHECK (
                (owner_user_id IS NULL AND ownership_claimed_at IS NULL)
                OR (
                    owner_user_id IS NOT NULL
                    AND ownership_claimed_at IS NOT NULL
                )
            );
    END IF;
END
$$;

ALTER TABLE robot_credentials
    ADD COLUMN IF NOT EXISTS device_token_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS device_token_rotated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS qr_token_hash VARCHAR(64),
    ADD COLUMN IF NOT EXISTS qr_token_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS qr_token_last_used_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'robot_credentials'
          AND column_name = 'expires_at'
    ) THEN
        EXECUTE '
            UPDATE robot_credentials
            SET device_token_expires_at =
                COALESCE(device_token_expires_at, expires_at)
        ';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'robot_credentials'
          AND column_name = 'rotated_at'
    ) THEN
        EXECUTE '
            UPDATE robot_credentials
            SET device_token_rotated_at =
                COALESCE(device_token_rotated_at, rotated_at)
        ';
    END IF;
END
$$;

UPDATE robot_credentials
SET qr_token_hash =
        md5('legacy-robot-qr-primary-' || robot_id::TEXT)
        || md5('legacy-robot-qr-secondary-' || robot_id::TEXT)
WHERE qr_token_hash IS NULL;

UPDATE robot_credentials
SET created_at = COALESCE(created_at, CURRENT_TIMESTAMP),
    updated_at = COALESCE(updated_at, CURRENT_TIMESTAMP);

ALTER TABLE robot_credentials
    ALTER COLUMN device_token_hash DROP NOT NULL,
    ALTER COLUMN qr_token_hash SET NOT NULL,
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN updated_at SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_robot_credentials_device_token_hash
    ON robot_credentials (device_token_hash)
    WHERE device_token_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_robot_credentials_qr_token_hash
    ON robot_credentials (qr_token_hash);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'robot_pairings_period_check'
    ) THEN
        ALTER TABLE robot_pairings
            ADD CONSTRAINT robot_pairings_period_check
            CHECK (unpaired_at IS NULL OR unpaired_at >= paired_at);
    END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_robot_pairings_active_robot
    ON robot_pairings (robot_id)
    WHERE unpaired_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_robot_pairings_active_pet
    ON robot_pairings (pet_id)
    WHERE unpaired_at IS NULL;

COMMIT;
