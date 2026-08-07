BEGIN;

CREATE TABLE IF NOT EXISTS dev_maintenance_runs (
    maintenance_key VARCHAR(150) PRIMARY KEY,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
DECLARE
    source_user_id BIGINT;
    target_user_id BIGINT;
    target_robot_id BIGINT;
    recorded_owner_user_id BIGINT;
    active_owner_user_id BIGINT;
    target_pet_id BIGINT;
    paired_time TIMESTAMPTZ := CURRENT_TIMESTAMP;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dev_maintenance_runs
        WHERE maintenance_key = '013_pair_device001_with_ssafy'
    ) THEN
        RETURN;
    END IF;

    SELECT app_user.id
    INTO source_user_id
    FROM users app_user
    WHERE LOWER(app_user.email) = 'rexsung1@gmail.com'
      AND app_user.deleted_at IS NULL;

    IF source_user_id IS NULL THEN
        RAISE EXCEPTION 'Active source user rexsung1@gmail.com was not found';
    END IF;

    SELECT app_user.id
    INTO target_user_id
    FROM users app_user
    WHERE LOWER(app_user.email) = 'ssafy@test.com'
      AND app_user.deleted_at IS NULL;

    IF target_user_id IS NULL THEN
        RAISE EXCEPTION 'Active target user ssafy@test.com was not found';
    END IF;

    SELECT robot.id, robot.owner_user_id
    INTO target_robot_id, recorded_owner_user_id
    FROM robots robot
    WHERE LOWER(robot.serial_number) = 'device-001'
    FOR UPDATE;

    IF target_robot_id IS NULL THEN
        RAISE EXCEPTION 'Robot device-001 was not found';
    END IF;

    IF recorded_owner_user_id IS NOT NULL
       AND recorded_owner_user_id NOT IN (source_user_id, target_user_id) THEN
        RAISE EXCEPTION
            'device-001 ownership belongs to an unexpected user id %',
            recorded_owner_user_id;
    END IF;

    SELECT pet.user_id
    INTO active_owner_user_id
    FROM robot_pairings pairing
    JOIN pets pet ON pet.id = pairing.pet_id
    WHERE pairing.robot_id = target_robot_id
      AND pairing.unpaired_at IS NULL;

    IF active_owner_user_id IS NOT NULL
       AND active_owner_user_id NOT IN (source_user_id, target_user_id) THEN
        RAISE EXCEPTION
            'device-001 is paired with an unexpected user id %',
            active_owner_user_id;
    END IF;

    IF active_owner_user_id = target_user_id THEN
        UPDATE pets pet
        SET name = '마실',
            updated_at = paired_time
        FROM robot_pairings pairing
        WHERE pairing.pet_id = pet.id
          AND pairing.robot_id = target_robot_id
          AND pairing.unpaired_at IS NULL;
    ELSE
        UPDATE robot_pairings pairing
        SET unpaired_at = paired_time
        WHERE pairing.robot_id = target_robot_id
          AND pairing.unpaired_at IS NULL;

        SELECT pet.id
        INTO target_pet_id
        FROM pets pet
        WHERE pet.user_id = target_user_id
          AND pet.name = '마실'
          AND pet.deleted_at IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM robot_pairings active_pairing
              WHERE active_pairing.pet_id = pet.id
                AND active_pairing.unpaired_at IS NULL
          )
        ORDER BY pet.id DESC
        LIMIT 1;

        IF target_pet_id IS NULL THEN
            INSERT INTO pets (
                user_id, name, created_at, updated_at
            ) VALUES (
                target_user_id, '마실', paired_time, paired_time
            )
            RETURNING id INTO target_pet_id;

            INSERT INTO pet_affinity_states (
                pet_id, affinity_score, affinity_level, mood, updated_at
            ) VALUES (
                target_pet_id, 0, 1, 'NEUTRAL', paired_time
            );
        END IF;

        INSERT INTO robot_pairings (
            pet_id, robot_id, paired_at
        ) VALUES (
            target_pet_id, target_robot_id, paired_time
        );
    END IF;

    UPDATE robots robot
    SET owner_user_id = target_user_id,
        ownership_claimed_at = CASE
            WHEN robot.owner_user_id = target_user_id
                THEN COALESCE(robot.ownership_claimed_at, paired_time)
            ELSE paired_time
        END,
        updated_at = paired_time
    WHERE robot.id = target_robot_id;

    UPDATE robot_credentials credential
    SET qr_token_last_used_at = paired_time,
        updated_at = paired_time
    WHERE credential.robot_id = target_robot_id;

    INSERT INTO dev_maintenance_runs (maintenance_key)
    VALUES ('013_pair_device001_with_ssafy');
END
$$;

COMMIT;
