BEGIN;

CREATE TABLE IF NOT EXISTS dev_maintenance_runs (
    maintenance_key VARCHAR(150) PRIMARY KEY,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TEMP TABLE cleanup_demo_pets ON COMMIT DROP AS
SELECT pet.id
FROM pets pet
JOIN users app_user ON app_user.id = pet.user_id
WHERE LOWER(app_user.email) = 'rexsung1@gmail.com'
  AND LOWER(pet.name) IN ('mungmung', 'daengdaeng')
  AND pet.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM dev_maintenance_runs maintenance
      WHERE maintenance.maintenance_key = '011_cleanup_rexsung_demo_pets'
  );

CREATE TEMP TABLE cleanup_demo_robots ON COMMIT DROP AS
SELECT DISTINCT pairing.robot_id
FROM robot_pairings pairing
JOIN cleanup_demo_pets target_pet ON target_pet.id = pairing.pet_id;

CREATE TEMP TABLE cleanup_demo_pairings ON COMMIT DROP AS
SELECT pairing.id
FROM robot_pairings pairing
JOIN cleanup_demo_pets target_pet ON target_pet.id = pairing.pet_id;

DELETE FROM walks walk
WHERE walk.robot_pairing_id IN (SELECT id FROM cleanup_demo_pairings);

DELETE FROM walk_proposals proposal
WHERE proposal.robot_pairing_id IN (SELECT id FROM cleanup_demo_pairings);

DELETE FROM robot_pairings pairing
WHERE pairing.id IN (SELECT id FROM cleanup_demo_pairings);

UPDATE robots robot
SET owner_user_id = NULL,
    ownership_claimed_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE robot.id IN (SELECT robot_id FROM cleanup_demo_robots)
  AND NOT EXISTS (
      SELECT 1
      FROM robot_pairings remaining_pairing
      WHERE remaining_pairing.robot_id = robot.id
        AND remaining_pairing.unpaired_at IS NULL
  );

UPDATE robot_credentials credential
SET qr_token_last_used_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE credential.robot_id IN (SELECT robot_id FROM cleanup_demo_robots);

-- 새 QR 원문은 DB나 Git에 저장하지 않고 사용자에게 이미지로만 전달한다.
UPDATE robot_credentials credential
SET qr_token_hash = 'c383797ee06496f6316870b7ee11a386d2e96874a81c139add7630f63a35b188',
    qr_token_expires_at = NULL,
    qr_token_last_used_at = NULL,
    updated_at = CURRENT_TIMESTAMP
FROM robots robot
WHERE credential.robot_id = robot.id
  AND LOWER(robot.serial_number) = 'device-001'
  AND robot.id IN (SELECT robot_id FROM cleanup_demo_robots);

DELETE FROM pets pet
WHERE pet.id IN (SELECT id FROM cleanup_demo_pets);

-- 정리 대상이 하나도 없었으면 키를 남기지 않는다. 무조건 기록하면 아무 일도
-- 하지 않은 실행이 "완료"로 박히고, 위의 device-001 QR 해시 보정까지 영구히
-- 비활성화된다. 실제로 그렇게 되어 dev 의 QR 등록이 막혔다.
INSERT INTO dev_maintenance_runs (maintenance_key)
SELECT '011_cleanup_rexsung_demo_pets'
WHERE EXISTS (SELECT 1 FROM cleanup_demo_pets)
ON CONFLICT (maintenance_key) DO NOTHING;

COMMIT;
