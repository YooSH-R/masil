BEGIN;

-- 닉네임 중복을 허용한다.
--
-- 이름이 두 갈래다. 초기 스키마가 `nickname VARCHAR(100) NOT NULL UNIQUE` 로
-- 컬럼 레벨 UNIQUE 를 붙였던 시기에 만들어진 DB(dev 포함)는 제약 이름이
-- `users_nickname_key` 로 자동 생성돼 있고, 명시적으로 이름을 준 환경은
-- `uq_users_nickname` 이다. 자동 생성된 인덱스는 제약이 잡고 있어서
-- `DROP INDEX` 로는 지워지지 않으므로 제약을 먼저 지워야 한다.
ALTER TABLE users
    DROP CONSTRAINT IF EXISTS uq_users_nickname;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_nickname_key;

-- 제약 없이 인덱스만 남은 환경 정리.
DROP INDEX IF EXISTS users_nickname_key;

COMMIT;
