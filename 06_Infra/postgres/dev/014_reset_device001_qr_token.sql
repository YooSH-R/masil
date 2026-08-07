BEGIN;

CREATE TABLE IF NOT EXISTS dev_maintenance_runs (
    maintenance_key VARCHAR(150) PRIMARY KEY,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
DECLARE
    updated_credentials INTEGER;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dev_maintenance_runs
        WHERE maintenance_key = '014_reset_device001_qr_token'
    ) THEN
        RETURN;
    END IF;

    UPDATE robot_credentials credential
    SET qr_token_hash =
            'c383797ee06496f6316870b7ee11a386d2e96874a81c139add7630f63a35b188',
        qr_token_expires_at = NULL,
        qr_token_last_used_at = NULL,
        updated_at = CURRENT_TIMESTAMP
    FROM robots robot
    WHERE credential.robot_id = robot.id
      AND LOWER(robot.serial_number) = 'device-001';

    GET DIAGNOSTICS updated_credentials = ROW_COUNT;
    IF updated_credentials <> 1 THEN
        RAISE EXCEPTION
            'Expected one credential for device-001, updated %',
            updated_credentials;
    END IF;

    INSERT INTO dev_maintenance_runs (maintenance_key)
    VALUES ('014_reset_device001_qr_token');
END
$$;

COMMIT;
