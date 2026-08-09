#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  $0 SERIAL_NUMBER MODEL_NAME [FIRMWARE_VERSION]
  $0 --device-token-only SERIAL_NUMBER
EOF
}

mode="full"
if [[ "${1:-}" == "--device-token-only" ]]; then
  if [[ $# -ne 2 ]]; then
    usage
    exit 2
  fi
  mode="device-token-only"
  serial_number="$2"
  model_name=""
  firmware_version=""
elif [[ $# -ge 2 && $# -le 3 ]]; then
  serial_number="$1"
  model_name="$2"
  firmware_version="${3:-}"
else
  usage
  exit 2
fi

# QR 이미지는 로컬에서 발급하는데 실제 DB 는 dev 클러스터에 있다. 대상을 고를 수
# 없으면 해시가 로컬 컨테이너에만 남아, 앱은 QR 을 정상으로 읽는데 서버가
# INVALID_QR_TOKEN 을 낸다. device-001~003 이 실제로 그 상태였다.
postgres_backend="${POSTGRES_BACKEND:-docker}"
postgres_container="${POSTGRES_CONTAINER:-pet-robot-postgres}"
postgres_pod="${POSTGRES_POD:-postgres-0}"
kubectl_bin="${KUBECTL_BIN:-kubectl}"

case "$postgres_backend" in
  docker)
    required_commands=(docker openssl sha256sum)
    ;;
  kubectl)
    if [[ -z "${K8S_NAMESPACE:-}" ]]; then
      echo "K8S_NAMESPACE is required when POSTGRES_BACKEND=kubectl." >&2
      exit 2
    fi
    required_commands=("$kubectl_bin" openssl sha256sum)
    ;;
  *)
    echo "POSTGRES_BACKEND must be either docker or kubectl." >&2
    exit 2
    ;;
esac

for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

# 사용법: postgres_psql VAR=VALUE ... -- '<sh -c 로 실행할 psql 명령>'  (SQL 은 stdin)
#
# 여기로 넘기는 값은 해시와 메타데이터뿐이다. qr_token·device_token 원문은
# 로컬 셸을 벗어나지 않으며 성공 출력에서 한 번만 보여준다.
postgres_psql() {
  local env_pairs=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    env_pairs+=("$1")
    shift
  done
  shift

  if [[ "$postgres_backend" == "kubectl" ]]; then
    "$kubectl_bin" -n "$K8S_NAMESPACE" exec -i "$postgres_pod" -- \
      env "${env_pairs[@]}" sh -c "$1"
  else
    local docker_env=()
    local pair
    for pair in "${env_pairs[@]}"; do
      docker_env+=(-e "$pair")
    done
    docker exec -i "${docker_env[@]}" "$postgres_container" sh -c "$1"
  fi
}

qr_expires_days="${QR_EXPIRES_DAYS:-30}"
device_token_expires_days="${DEVICE_TOKEN_EXPIRES_DAYS:-365}"
if [[ "$mode" == "full" && ! "$qr_expires_days" =~ ^[1-9][0-9]*$ ]]; then
  echo "QR_EXPIRES_DAYS must be a positive integer." >&2
  exit 2
fi

if [[ ! "$device_token_expires_days" =~ ^[1-9][0-9]*$ ]]; then
  echo "DEVICE_TOKEN_EXPIRES_DAYS must be a positive integer." >&2
  exit 2
fi

qr_token=""
qr_token_hash=""
if [[ "$mode" == "full" ]]; then
  qr_token="$(
    openssl rand -base64 32 |
      tr '+/' '-_' |
      tr -d '=\r\n'
  )"
  qr_token_hash="$(
    printf '%s' "$qr_token" |
      sha256sum |
      awk '{print $1}'
  )"
fi
device_token="$(
  openssl rand -base64 32 |
    tr '+/' '-_' |
    tr -d '=\r\n'
)"
device_token_hash="$(
  printf '%s' "$device_token" |
    sha256sum |
    awk '{print $1}'
)"

if [[ "$mode" == "device-token-only" ]]; then
  robot_id="$(
    postgres_psql \
      PROVISION_SERIAL="$serial_number" \
      PROVISION_DEVICE_HASH="$device_token_hash" \
      PROVISION_DEVICE_EXPIRES_DAYS="$device_token_expires_days" \
      -- '
        psql -X -qAt -v ON_ERROR_STOP=1 \
          -U "$POSTGRES_USER" \
          -d "$POSTGRES_DB" \
          --set=serial="$PROVISION_SERIAL" \
          --set=device_hash="$PROVISION_DEVICE_HASH" \
          --set=device_expires_days="$PROVISION_DEVICE_EXPIRES_DAYS"
      ' <<'SQL'
UPDATE robot_credentials AS credential
SET device_token_hash = :'device_hash',
    device_token_expires_at =
        CURRENT_TIMESTAMP + make_interval(days => :device_expires_days),
    device_token_rotated_at = CURRENT_TIMESTAMP,
    updated_at = CURRENT_TIMESTAMP
FROM robots AS robot
WHERE robot.id = credential.robot_id
  AND robot.serial_number = :'serial'
RETURNING credential.robot_id;
SQL
  )"
else
  robot_id="$(
  postgres_psql \
    PROVISION_SERIAL="$serial_number" \
    PROVISION_MODEL="$model_name" \
    PROVISION_FIRMWARE="$firmware_version" \
    PROVISION_QR_HASH="$qr_token_hash" \
    PROVISION_QR_EXPIRES_DAYS="$qr_expires_days" \
    PROVISION_DEVICE_HASH="$device_token_hash" \
    PROVISION_DEVICE_EXPIRES_DAYS="$device_token_expires_days" \
    -- '
      psql -X -qAt -v ON_ERROR_STOP=1 \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --set=serial="$PROVISION_SERIAL" \
        --set=model="$PROVISION_MODEL" \
        --set=firmware="$PROVISION_FIRMWARE" \
        --set=qr_hash="$PROVISION_QR_HASH" \
        --set=expires_days="$PROVISION_QR_EXPIRES_DAYS" \
        --set=device_hash="$PROVISION_DEVICE_HASH" \
        --set=device_expires_days="$PROVISION_DEVICE_EXPIRES_DAYS"
    ' <<'SQL'
WITH saved_robot AS (
    INSERT INTO robots (
        serial_number,
        model_name,
        firmware_version
    )
    VALUES (
        :'serial',
        :'model',
        NULLIF(:'firmware', '')
    )
    ON CONFLICT (serial_number)
    DO UPDATE SET
        model_name = CASE
            WHEN robots.owner_user_id IS NULL
                THEN EXCLUDED.model_name
            ELSE robots.model_name
        END,
        firmware_version = CASE
            WHEN robots.owner_user_id IS NULL
                THEN EXCLUDED.firmware_version
            ELSE robots.firmware_version
        END,
        updated_at = CURRENT_TIMESTAMP
    RETURNING id
),
saved_credential AS (
    INSERT INTO robot_credentials (
        robot_id,
        device_token_hash,
        device_token_expires_at,
        device_token_rotated_at,
        qr_token_hash,
        qr_token_expires_at
    )
    SELECT
        id,
        :'device_hash',
        CURRENT_TIMESTAMP + make_interval(days => :device_expires_days),
        CURRENT_TIMESTAMP,
        :'qr_hash',
        CURRENT_TIMESTAMP + make_interval(days => :expires_days)
    FROM saved_robot
    ON CONFLICT (robot_id)
    DO UPDATE SET
        device_token_hash = EXCLUDED.device_token_hash,
        device_token_expires_at = EXCLUDED.device_token_expires_at,
        device_token_rotated_at = EXCLUDED.device_token_rotated_at,
        qr_token_hash = EXCLUDED.qr_token_hash,
        qr_token_expires_at = EXCLUDED.qr_token_expires_at,
        qr_token_last_used_at = NULL,
        updated_at = CURRENT_TIMESTAMP
    WHERE robot_credentials.qr_token_hash IS NULL
       OR EXISTS (
           SELECT 1
           FROM robots
           WHERE robots.id = robot_credentials.robot_id
             AND robots.owner_user_id IS NULL
       )
    RETURNING robot_id
)
SELECT robot_id
FROM saved_credential;
SQL
  )"
fi

if [[ -z "$robot_id" ]]; then
  if [[ "$mode" == "device-token-only" ]]; then
    echo "Device token rotation failed: robot or credentials not found." >&2
  else
    echo "Provisioning failed: an owned robot cannot rotate an existing QR." >&2
  fi
  exit 1
fi

if [[ "$mode" == "device-token-only" ]]; then
  echo "Device HTTP token rotation completed."
  echo "robot_id=$robot_id"
  echo "serial_number=$serial_number"
  echo "device_token=$device_token"
  echo "The raw device token is shown only in this output. Store it securely."
  echo "The robot ownership and QR credential were not changed."
else
  echo "Robot QR provisioning completed."
  echo "robot_id=$robot_id"
  echo "serial_number=$serial_number"
  echo "qr_token=$qr_token"
  echo "device_token=$device_token"
  echo "Raw tokens are shown only in this output. Store them securely."
  echo "Encode qr_token as the QR image and install device_token on the robot."
fi
