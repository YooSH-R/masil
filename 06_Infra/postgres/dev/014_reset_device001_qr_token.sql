BEGIN;

CREATE TABLE IF NOT EXISTS dev_maintenance_runs (
    maintenance_key VARCHAR(150) PRIMARY KEY,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
DECLARE
    qr_hash CONSTANT VARCHAR(64) :=
        'c383797ee06496f6316870b7ee11a386d2e96874a81c139add7630f63a35b188';
    target_robot_id BIGINT;
    conflicting_robot_id BIGINT;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dev_maintenance_runs
        WHERE maintenance_key = '014_reset_device001_qr_token'
    ) THEN
        RETURN;
    END IF;

    SELECT robot.id
    INTO target_robot_id
    FROM robots robot
    WHERE LOWER(robot.serial_number) = 'device-001'
    FOR UPDATE;

    IF target_robot_id IS NULL THEN
        RAISE NOTICE
            'Robot device-001 was not found; retrying on the next deployment';
        RETURN;
    END IF;

    -- uq_robot_credentials_qr_token_hash 위반은 이 파일이 마지막 인자라
    -- 파이프라인 전체(set -eu)를 세운다. 다른 로봇이 같은 해시를 들고 있으면
    -- 배포를 막지 않고 알림만 남긴다.
    SELECT credential.robot_id
    INTO conflicting_robot_id
    FROM robot_credentials credential
    WHERE credential.qr_token_hash = qr_hash
      AND credential.robot_id <> target_robot_id;

    IF conflicting_robot_id IS NOT NULL THEN
        RAISE NOTICE
            'device-001 QR hash is already held by robot id %; skipping',
            conflicting_robot_id;
        RETURN;
    END IF;

    -- UPDATE 가 아니라 UPSERT 여야 한다. device-001 은 robot_credentials 행
    -- 자체가 없었고, 013 이 QR 을 거치지 않고 robot_pairings 를 직접 넣어
    -- 페어링을 만들기 때문에 자격증명이 비어 있어도 겉으로는 정상이었다.
    -- 그 상태에서 펫을 지우고 QR 로 재등록하면 findByQrTokenHash 가 아무것도
    -- 찾지 못해 INVALID_QR_TOKEN 이 난다.
    INSERT INTO robot_credentials (
        robot_id,
        qr_token_hash,
        qr_token_expires_at,
        qr_token_last_used_at,
        created_at,
        updated_at
    ) VALUES (
        target_robot_id,
        qr_hash,
        NULL,
        NULL,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (robot_id) DO UPDATE
    SET qr_token_hash = EXCLUDED.qr_token_hash,
        qr_token_expires_at = NULL,
        qr_token_last_used_at = NULL,
        updated_at = CURRENT_TIMESTAMP;

    INSERT INTO dev_maintenance_runs (maintenance_key)
    VALUES ('014_reset_device001_qr_token');
END
$$;

COMMIT;
