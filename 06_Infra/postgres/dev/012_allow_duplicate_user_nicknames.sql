BEGIN;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS uq_users_nickname;

DROP INDEX IF EXISTS users_nickname_key;

COMMIT;
