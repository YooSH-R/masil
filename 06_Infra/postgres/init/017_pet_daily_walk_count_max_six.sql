-- 하루 산책 횟수 상한을 24 → 6 으로 내린다.
--
-- 산책일지 S3 경로가 `.../{yyyy-MM-dd}/session{1~6}/` 이라 하루 7회 이상은
-- 담을 자리가 없다. 상한을 24 로 열어두면 사용자가 10회로 설정했을 때 7번째
-- 산책부터 일지가 조용히 사라진다.
--
-- 016 은 제약이 이미 있으면 건너뛰므로(IF NOT EXISTS) 그 파일을 고쳐도 기존
-- DB 에는 반영되지 않는다. 그래서 별도 번호로 다시 건다.

BEGIN;

-- 상한을 넘는 기존 값을 먼저 내려야 새 제약을 걸 수 있다.
UPDATE pets
SET daily_walk_count = 6,
    updated_at = CURRENT_TIMESTAMP
WHERE daily_walk_count > 6;

-- 지우고 다시 거는 방식이라 여러 번 실행해도 결과가 같다.
ALTER TABLE pets
    DROP CONSTRAINT IF EXISTS pets_daily_walk_count_check;

ALTER TABLE pets
    ADD CONSTRAINT pets_daily_walk_count_check
    CHECK (daily_walk_count BETWEEN 1 AND 6);

COMMIT;
