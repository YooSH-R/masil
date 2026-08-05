BEGIN;

-- 기존 사진 업로드 및 분석 테이블은 다른 기능에서 사용하므로 보존한다.
-- 이 마이그레이션은 산책일지 메타데이터만 추가한다.

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
