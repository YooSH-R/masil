BEGIN;

DO $migration$
DECLARE
    legacy_table TEXT;
    existing_rows BIGINT;
BEGIN
    FOREACH legacy_table IN ARRAY ARRAY[
        'photo_analyses',
        'walk_photos',
        'robot_photos'
    ]
    LOOP
        IF to_regclass('public.' || legacy_table) IS NOT NULL THEN
            EXECUTE format(
                'SELECT COUNT(*) FROM %I',
                legacy_table
            ) INTO existing_rows;

            IF existing_rows > 0 THEN
                RAISE EXCEPTION
                    'Migration stopped: table % contains % row(s)',
                    legacy_table,
                    existing_rows
                    USING HINT =
                        'Back up and explicitly approve deletion before retrying.';
            END IF;
        END IF;
    END LOOP;
END
$migration$;

DROP TABLE IF EXISTS photo_analyses;
DROP TABLE IF EXISTS walk_photos;
DROP TABLE IF EXISTS robot_photos;

CREATE TABLE IF NOT EXISTS walk_diaries (
    walk_id BIGINT PRIMARY KEY REFERENCES walks(id) ON DELETE CASCADE,
    walk_date DATE NOT NULL,
    session_no INTEGER NOT NULL,
    object_prefix VARCHAR(500) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT walk_diaries_session_check CHECK (session_no > 0)
);

CREATE INDEX IF NOT EXISTS idx_pets_user_active
    ON pets (user_id, id)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_robot_pairings_pet_lookup
    ON robot_pairings (pet_id, id);

CREATE INDEX IF NOT EXISTS idx_walks_pairing_lookup
    ON walks (robot_pairing_id, id);

DROP INDEX IF EXISTS idx_walk_diaries_date_session;

CREATE INDEX IF NOT EXISTS idx_walk_diaries_feed_order
    ON walk_diaries (walk_date DESC, session_no ASC, walk_id ASC);

COMMIT;
