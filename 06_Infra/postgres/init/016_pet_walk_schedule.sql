-- 펫별 하루 산책 횟수. 산책 제안 간격을 이 값으로 정한다.
--
-- 앱의 "산책 주기 설정" 은 지금까지 화면에만 남고 서버로 오지 않았다. 이 컬럼이
-- 생기면서 설정값이 WalkProposalCreationService 의 제안 간격에 실제로 반영된다.
--
-- 기존 DB 를 위한 마이그레이션이다. 새로 만드는 DB 는 001_schema.sql 이 같은
-- 컬럼과 제약을 이미 포함한다.

BEGIN;

ALTER TABLE pets
    ADD COLUMN IF NOT EXISTS daily_walk_count INTEGER NOT NULL DEFAULT 2;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'pets_daily_walk_count_check'
    ) THEN
        ALTER TABLE pets
            ADD CONSTRAINT pets_daily_walk_count_check
            CHECK (daily_walk_count BETWEEN 1 AND 24);
    END IF;
END
$$;

COMMIT;
