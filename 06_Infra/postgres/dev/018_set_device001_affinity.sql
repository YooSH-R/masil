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
    -- 컬럼명과 겹치지 않는 이름을 쓴다. dev_maintenance_runs.maintenance_key 와
    -- 같은 이름이면 PL/pgSQL 이 어느 쪽인지 몰라 실행 시점에 ambiguous 오류를 낸다.
    run_key CONSTANT VARCHAR(150) := '018_set_device001_affinity';
    target_score CONSTANT INTEGER := 57;
    target_pet_id BIGINT;
    target_level INTEGER;
    target_mood VARCHAR(30);
BEGIN
    IF EXISTS (
        SELECT 1
        FROM dev_maintenance_runs
        WHERE dev_maintenance_runs.maintenance_key = run_key
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

    -- 페어링이 없어도 배포를 막지 않는다(014·015 와 같은 방침). 시연 준비 중에
    -- 펫을 지웠다 다시 만드는 일이 잦은데, 그때마다 마이그레이션 단계가 실패하면
    -- 백엔드 배포까지 함께 멈춘다. 친밀도가 안 맞는 건 화면에서 바로 보이는
    -- 문제라 조용히 틀어질 위험도 없다.
    --
    -- 완료 표시를 남기기 전에 빠져나가므로 다음 배포에서 다시 시도한다.
    IF target_pet_id IS NULL THEN
        RAISE NOTICE
            'device-001 has no active pairing; retrying on the next deployment';
        RETURN;
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

    INSERT INTO dev_maintenance_runs (maintenance_key) VALUES (run_key);
END
$$;

COMMIT;
