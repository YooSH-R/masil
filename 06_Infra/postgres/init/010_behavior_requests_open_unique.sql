BEGIN;

-- 사전검사와 부분 고유 인덱스 생성 사이에 새 열린 요청이 추가되지 않도록 막는다.
LOCK TABLE behavior_requests IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (
        SELECT robot_id, request_type
        FROM behavior_requests
        WHERE status IN ('PENDING', 'PUBLISHED', 'RECEIVED')
        GROUP BY robot_id, request_type
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            '010_behavior_requests_open_unique: 같은 로봇과 요청 유형에 열린 요청이 중복되어 있습니다';
    END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_behavior_requests_open_robot_type
    ON behavior_requests (robot_id, request_type)
    WHERE status IN ('PENDING', 'PUBLISHED', 'RECEIVED');

CREATE INDEX IF NOT EXISTS idx_behavior_requests_robot_type_created
    ON behavior_requests (robot_id, request_type, created_at DESC);

COMMIT;
