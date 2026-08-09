-- device-001 과 짝지어진 펫의 친밀도를 시연용 값으로 맞춘다.
--
-- 친밀도는 원래 산책·교감 이벤트가 쌓여 오른다(RobotMqttApplicationService).
-- 시연에서는 그만큼 쌓을 시간이 없어서 시작값을 직접 넣는다.
--
-- 점수에 딸린 값도 서버와 같은 규칙으로 계산해 넣는다. 점수만 바꾸면 화면의
-- 레벨·기분이 점수와 어긋난 채로 보인다.
--   level = min(5, score / 20 + 1)
--   mood  = score >= 80 HAPPY / >= 50 FRIENDLY / >= 20 CALM / 그 미만 WARY
-- 57점이면 level 3, mood FRIENDLY 다.
--
-- 한 번만 돈다. 파이프라인이 배포할 때마다 이 스크립트를 다시 실행하는데,
-- 그때마다 되돌리면 시연 중에 오른 친밀도가 도로 57 로 깎인다.

BEGIN;

CREATE TABLE IF NOT EXISTS dev_maintenance_runs (
    maintenance_key VARCHAR(150) PRIMARY KEY,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
DECLARE
    maintenance_key CONSTANT VARCHAR(150) := '018_set_device001_affinity';
    target_score CONSTANT INTEGER := 57;
    target_pet_id BIGINT;
    target_level INTEGER;
    target_mood VARCHAR(30);
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dev_maintenance_runs
        WHERE dev_maintenance_runs.maintenance_key = maintenance_key
    ) THEN
        RETURN;
    END IF;

    SELECT pairing.pet_id
    INTO target_pet_id
    FROM robot_pairings pairing
    JOIN robots robot ON robot.id = pairing.robot_id
    JOIN pets pet ON pet.id = pairing.pet_id
    WHERE LOWER(robot.serial_number) = 'device-001'
      AND pairing.unpaired_at IS NULL
      AND pet.deleted_at IS NULL;

    IF target_pet_id IS NULL THEN
        RAISE EXCEPTION
            'device-001 에 연결된 활성 페어링이 없어 친밀도를 설정할 수 없습니다';
    END IF;

    target_level := LEAST(5, target_score / 20 + 1);
    target_mood := CASE
        WHEN target_score >= 80 THEN 'HAPPY'
        WHEN target_score >= 50 THEN 'FRIENDLY'
        WHEN target_score >= 20 THEN 'CALM'
        ELSE 'WARY'
    END;

    -- 페어링을 만든 스크립트(013)가 상태 행까지 만들어 두지만, 손으로 만든
    -- 펫에는 없을 수 있어 없으면 넣고 있으면 고친다.
    INSERT INTO pet_affinity_states (
        pet_id, affinity_score, affinity_level, mood, updated_at
    ) VALUES (
        target_pet_id, target_score, target_level, target_mood, CURRENT_TIMESTAMP
    )
    ON CONFLICT (pet_id) DO UPDATE
    SET affinity_score = EXCLUDED.affinity_score,
        affinity_level = EXCLUDED.affinity_level,
        mood = EXCLUDED.mood,
        updated_at = CURRENT_TIMESTAMP;

    INSERT INTO dev_maintenance_runs (maintenance_key) VALUES (maintenance_key);
END
$$;

COMMIT;
