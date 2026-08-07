-- 팀이 들고 있는 시연용 QR 이미지(Mysil-device-00N-qr.png)와 dev DB 를 맞춘다.
--
-- provision-robot-qr.sh 는 원래 로컬 docker 컨테이너만 대상으로 동작했기 때문에
-- QR 이미지는 발급됐는데 dev 클러스터 DB 에는 해시가 들어가지 않았다. 그 결과
-- device-002 는 이미지와 다른 해시를 들고 있었고 device-003 은 robots 행조차
-- 없었다. 두 기기 모두 QR 스캔 등록이 INVALID_QR_TOKEN 으로 실패한다.
--
-- 저장하는 값은 SHA-256 해시뿐이고 QR 원문은 Git 에 두지 않는다. QR 을 새로
-- 발급하면 이 파일의 해시도 함께 갱신해야 한다.

BEGIN;

CREATE TABLE IF NOT EXISTS dev_maintenance_runs (
    maintenance_key VARCHAR(150) PRIMARY KEY,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
DECLARE
    demo_device RECORD;
    target_robot_id BIGINT;
    conflicting_robot_id BIGINT;
    skipped_devices INTEGER := 0;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dev_maintenance_runs
        WHERE maintenance_key = '015_sync_demo_device_qr_tokens'
    ) THEN
        RETURN;
    END IF;

    FOR demo_device IN
        SELECT *
        FROM (VALUES
            (
                'device-002',
                'PetBot Demo',
                'b7d09a60a8da45147f03de8a8d8601ece087bff1754bce648314dc621f456a26'
            ),
            (
                'device-003',
                'MYSIL_DEMO',
                'f4554ecee2aab0aea85bf2b86bbd3e960534389c7bb261973af33acececea846'
            )
        ) AS demo(serial_number, model_name, qr_token_hash)
    LOOP
        SELECT robot.id
        INTO target_robot_id
        FROM robots robot
        WHERE LOWER(robot.serial_number) = demo_device.serial_number
        FOR UPDATE;

        IF target_robot_id IS NULL THEN
            INSERT INTO robots (
                serial_number, model_name, created_at, updated_at
            ) VALUES (
                demo_device.serial_number,
                demo_device.model_name,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP
            )
            RETURNING id INTO target_robot_id;
        END IF;

        -- 등록 직후 앱이 GET /v1/robots/{id}/status 를 호출한다. 상태 행이
        -- 없으면 404 가 나서 등록은 됐는데 화면이 비는 것처럼 보인다.
        INSERT INTO robot_current_states (
            robot_id, online, mode, battery_level, docked, updated_at
        ) VALUES (
            target_robot_id, FALSE, 'IDLE', 0, FALSE, CURRENT_TIMESTAMP
        )
        ON CONFLICT (robot_id) DO NOTHING;

        -- uq_robot_credentials_qr_token_hash 위반은 파이프라인 전체(set -eu)를
        -- 세운다. 다른 로봇이 같은 해시를 들고 있으면 배포를 막지 않고
        -- 알림만 남기고 다음 배포에서 다시 시도한다.
        SELECT credential.robot_id
        INTO conflicting_robot_id
        FROM robot_credentials credential
        WHERE credential.qr_token_hash = demo_device.qr_token_hash
          AND credential.robot_id <> target_robot_id;

        IF conflicting_robot_id IS NOT NULL THEN
            RAISE NOTICE
                '% QR hash is already held by robot id %; skipping',
                demo_device.serial_number, conflicting_robot_id;
            skipped_devices := skipped_devices + 1;
            CONTINUE;
        END IF;

        INSERT INTO robot_credentials (
            robot_id,
            qr_token_hash,
            qr_token_expires_at,
            qr_token_last_used_at,
            created_at,
            updated_at
        ) VALUES (
            target_robot_id,
            demo_device.qr_token_hash,
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
    END LOOP;

    -- 하나라도 건너뛰었으면 키를 남기지 않는다. 무조건 기록하면 아무 일도
    -- 하지 않은 실행이 "완료"로 박혀 영구히 재시도되지 않는다(011 사례).
    IF skipped_devices > 0 THEN
        RAISE NOTICE
            '% demo device(s) were skipped; retrying on the next deployment',
            skipped_devices;
        RETURN;
    END IF;

    INSERT INTO dev_maintenance_runs (maintenance_key)
    VALUES ('015_sync_demo_device_qr_tokens');
END
$$;

COMMIT;
