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

for command_name in docker openssl sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

postgres_container="${POSTGRES_CONTAINER:-pet-robot-postgres}"
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
    docker exec -i \
      -e PROVISION_SERIAL="$serial_number" \
      -e PROVISION_DEVICE_HASH="$device_token_hash" \
      -e PROVISION_DEVICE_EXPIRES_DAYS="$device_token_expires_days" \
      "$postgres_container" \
      sh -c '
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
  docker exec -i \
    -e PROVISION_SERIAL="$serial_number" \
    -e PROVISION_MODEL="$model_name" \
    -e PROVISION_FIRMWARE="$firmware_version" \
    -e PROVISION_QR_HASH="$qr_token_hash" \
    -e PROVISION_QR_EXPIRES_DAYS="$qr_expires_days" \
    -e PROVISION_DEVICE_HASH="$device_token_hash" \
    -e PROVISION_DEVICE_EXPIRES_DAYS="$device_token_expires_days" \
    "$postgres_container" \
    sh -c '
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
