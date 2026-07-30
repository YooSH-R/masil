BEGIN;

ALTER TABLE robots
    ADD COLUMN IF NOT EXISTS owner_user_id BIGINT REFERENCES users(id);

ALTER TABLE robots
    ADD COLUMN IF NOT EXISTS ownership_claimed_at TIMESTAMPTZ;

ALTER TABLE robots
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE robots
SET updated_at = COALESCE(created_at, CURRENT_TIMESTAMP)
WHERE updated_at IS NULL;

ALTER TABLE robots
    ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN updated_at SET NOT NULL;

WITH first_owners AS (
    SELECT DISTINCT ON (pairing.robot_id)
        pairing.robot_id,
        pet.user_id,
        pairing.paired_at
    FROM robot_pairings pairing
    JOIN pets pet ON pet.id = pairing.pet_id
    ORDER BY pairing.robot_id, pairing.paired_at, pairing.id
)
UPDATE robots robot
SET owner_user_id = first_owner.user_id,
    ownership_claimed_at = first_owner.paired_at
FROM first_owners first_owner
WHERE robot.id = first_owner.robot_id
  AND robot.owner_user_id IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'robots_ownership_claim_check'
          AND conrelid = 'robots'::regclass
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

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'robot_credentials'
          AND column_name = 'expires_at'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'robot_credentials'
          AND column_name = 'device_token_expires_at'
    ) THEN
        ALTER TABLE robot_credentials
            RENAME COLUMN expires_at TO device_token_expires_at;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'robot_credentials'
          AND column_name = 'rotated_at'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'robot_credentials'
          AND column_name = 'device_token_rotated_at'
    ) THEN
        ALTER TABLE robot_credentials
            RENAME COLUMN rotated_at TO device_token_rotated_at;
    END IF;
END
$$;

ALTER TABLE robot_credentials
    ALTER COLUMN device_token_hash DROP NOT NULL;

ALTER TABLE robot_credentials
    ADD COLUMN IF NOT EXISTS qr_token_hash VARCHAR(64);

ALTER TABLE robot_credentials
    ADD COLUMN IF NOT EXISTS qr_token_expires_at TIMESTAMPTZ;

ALTER TABLE robot_credentials
    ADD COLUMN IF NOT EXISTS qr_token_last_used_at TIMESTAMPTZ;

ALTER TABLE robot_credentials
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;

ALTER TABLE robot_credentials
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE robot_credentials
SET created_at = COALESCE(created_at, CURRENT_TIMESTAMP),
    updated_at = COALESCE(updated_at, CURRENT_TIMESTAMP)
WHERE created_at IS NULL
   OR updated_at IS NULL;

ALTER TABLE robot_credentials
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP,
    ALTER COLUMN updated_at SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS robot_credentials_device_token_hash_key
    ON robot_credentials (device_token_hash);

CREATE UNIQUE INDEX IF NOT EXISTS robot_credentials_qr_token_hash_key
    ON robot_credentials (qr_token_hash);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM robot_credentials
        WHERE qr_token_hash IS NULL
    ) THEN
        ALTER TABLE robot_credentials
            ALTER COLUMN qr_token_hash SET NOT NULL;
    END IF;
END
$$;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'robot_pairings'
          AND column_name = 'user_id'
    ) THEN
        ALTER TABLE robot_pairings
            ALTER COLUMN user_id DROP NOT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'robot_pairings_period_check'
          AND conrelid = 'robot_pairings'::regclass
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
