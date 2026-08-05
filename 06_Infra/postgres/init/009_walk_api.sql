BEGIN;

-- 검증과 제약/인덱스 생성 사이에 산책 데이터가 바뀌지 않도록 막는다.
-- 배포 시 이 마이그레이션을 백엔드 롤아웃보다 먼저 적용해야 한다.
LOCK TABLE walk_proposals, walks, walk_locations
    IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE walks
    ALTER COLUMN started_at DROP NOT NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM walk_proposals
        WHERE status NOT IN ('PENDING', 'ACCEPTED', 'DECLINED', 'EXPIRED')
    ) THEN
        RAISE EXCEPTION
            '009_walk_api: walk_proposals에 지원하지 않는 status가 있습니다';
    END IF;

    IF EXISTS (
        SELECT 1 FROM walk_proposals
        WHERE (expires_at IS NOT NULL AND expires_at <= proposed_at)
           OR (status IN ('ACCEPTED', 'DECLINED') AND responded_at IS NULL)
           OR (status IN ('PENDING', 'EXPIRED') AND responded_at IS NOT NULL)
    ) THEN
        RAISE EXCEPTION
            '009_walk_api: walk_proposals의 만료/응답 상태 데이터가 유효하지 않습니다';
    END IF;

    IF EXISTS (
        SELECT robot_pairing_id
        FROM walk_proposals
        WHERE status = 'PENDING'
        GROUP BY robot_pairing_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            '009_walk_api: 같은 페어링에 PENDING 제안이 중복되어 있습니다';
    END IF;

    IF EXISTS (
        SELECT 1 FROM walks
        WHERE status NOT IN (
            'READY', 'ACTIVE', 'PROCESSING', 'COMPLETED', 'CANCELLED'
        )
           OR (ended_at IS NOT NULL
               AND (started_at IS NULL OR ended_at < started_at))
           OR NOT (
                (status = 'READY' AND started_at IS NULL AND ended_at IS NULL)
                OR (status = 'ACTIVE' AND started_at IS NOT NULL AND ended_at IS NULL)
                OR (status = 'PROCESSING' AND started_at IS NOT NULL AND ended_at IS NOT NULL)
                OR (
                    status = 'COMPLETED'
                    AND started_at IS NOT NULL
                    AND ended_at IS NOT NULL
                    AND distance_meters IS NOT NULL
                    AND duration_seconds IS NOT NULL
                )
                OR status = 'CANCELLED'
           )
    ) THEN
        RAISE EXCEPTION
            '009_walk_api: walks의 상태/시간 데이터가 새 생명주기 규칙과 맞지 않습니다';
    END IF;

    IF EXISTS (
        SELECT robot_pairing_id
        FROM walks
        WHERE status IN ('READY', 'ACTIVE', 'PROCESSING')
        GROUP BY robot_pairing_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            '009_walk_api: 같은 페어링에 열린 산책이 중복되어 있습니다';
    END IF;

    IF EXISTS (
        SELECT 1 FROM walk_locations
        WHERE sequence_no < 0
           OR (accuracy_meters IS NOT NULL
               AND (accuracy_meters < 0 OR accuracy_meters > 50))
    ) THEN
        RAISE EXCEPTION
            '009_walk_api: walk_locations의 sequence/accuracy 데이터가 유효하지 않습니다';
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walk_proposals_status_check'
          AND conrelid = 'walk_proposals'::regclass
    ) THEN
        ALTER TABLE walk_proposals
            ADD CONSTRAINT walk_proposals_status_check
            CHECK (status IN ('PENDING', 'ACCEPTED', 'DECLINED', 'EXPIRED'));
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walk_proposals_expiry_check'
          AND conrelid = 'walk_proposals'::regclass
    ) THEN
        ALTER TABLE walk_proposals
            ADD CONSTRAINT walk_proposals_expiry_check
            CHECK (expires_at IS NULL OR expires_at > proposed_at);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walk_proposals_response_check'
          AND conrelid = 'walk_proposals'::regclass
    ) THEN
        ALTER TABLE walk_proposals
            ADD CONSTRAINT walk_proposals_response_check
            CHECK (
                (status IN ('ACCEPTED', 'DECLINED') AND responded_at IS NOT NULL)
                OR
                (status IN ('PENDING', 'EXPIRED') AND responded_at IS NULL)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walks_status_check'
          AND conrelid = 'walks'::regclass
    ) THEN
        ALTER TABLE walks
            ADD CONSTRAINT walks_status_check
            CHECK (
                status IN (
                    'READY',
                    'ACTIVE',
                    'PROCESSING',
                    'COMPLETED',
                    'CANCELLED'
                )
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walks_time_order_check'
          AND conrelid = 'walks'::regclass
    ) THEN
        ALTER TABLE walks
            ADD CONSTRAINT walks_time_order_check
            CHECK (
                ended_at IS NULL
                OR (started_at IS NOT NULL AND ended_at >= started_at)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walks_lifecycle_check'
          AND conrelid = 'walks'::regclass
    ) THEN
        ALTER TABLE walks
            ADD CONSTRAINT walks_lifecycle_check
            CHECK (
                (status = 'READY' AND started_at IS NULL AND ended_at IS NULL)
                OR (status = 'ACTIVE' AND started_at IS NOT NULL AND ended_at IS NULL)
                OR (status = 'PROCESSING' AND started_at IS NOT NULL AND ended_at IS NOT NULL)
                OR (
                    status = 'COMPLETED'
                    AND started_at IS NOT NULL
                    AND ended_at IS NOT NULL
                    AND distance_meters IS NOT NULL
                    AND duration_seconds IS NOT NULL
                )
                OR status = 'CANCELLED'
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walk_locations_sequence_check'
          AND conrelid = 'walk_locations'::regclass
    ) THEN
        ALTER TABLE walk_locations
            ADD CONSTRAINT walk_locations_sequence_check
            CHECK (sequence_no >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'walk_locations_accuracy_check'
          AND conrelid = 'walk_locations'::regclass
    ) THEN
        ALTER TABLE walk_locations
            ADD CONSTRAINT walk_locations_accuracy_check
            CHECK (
                accuracy_meters IS NULL
                OR accuracy_meters BETWEEN 0 AND 50
            );
    END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_walk_proposals_pairing_pending
    ON walk_proposals (robot_pairing_id)
    WHERE status = 'PENDING';

CREATE INDEX IF NOT EXISTS idx_walk_proposals_current
    ON walk_proposals (robot_pairing_id, proposed_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_walk_proposals_pending_expires
    ON walk_proposals (expires_at)
    WHERE status = 'PENDING' AND expires_at IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_walks_pairing_open
    ON walks (robot_pairing_id)
    WHERE status IN ('READY', 'ACTIVE', 'PROCESSING');

CREATE INDEX IF NOT EXISTS idx_walks_pairing_created
    ON walks (robot_pairing_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_walks_pairing_completed_ended
    ON walks (robot_pairing_id, ended_at DESC)
    WHERE status = 'COMPLETED';

CREATE TABLE IF NOT EXISTS walk_location_batch_requests (
    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    walk_id BIGINT NOT NULL REFERENCES walks(id) ON DELETE CASCADE,
    idempotency_key VARCHAR(100) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    received_count INTEGER NOT NULL,
    saved_count INTEGER NOT NULL,
    rejected_count INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_walk_location_batch_request
        UNIQUE (walk_id, idempotency_key),
    CONSTRAINT walk_location_batch_counts_check
        CHECK (
            received_count >= 0
            AND saved_count >= 0
            AND rejected_count >= 0
            AND saved_count + rejected_count <= received_count
        )
);

CREATE INDEX IF NOT EXISTS idx_walk_location_batch_requests_created
    ON walk_location_batch_requests (created_at, id);

COMMIT;
