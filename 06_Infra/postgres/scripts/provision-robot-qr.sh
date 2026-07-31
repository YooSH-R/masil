#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 SERIAL_NUMBER MODEL_NAME [FIRMWARE_VERSION]" >&2
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
serial_number="$1"
model_name="$2"
firmware_version="${3:-}"

if [[ ! "$qr_expires_days" =~ ^[1-9][0-9]*$ ]]; then
  echo "QR_EXPIRES_DAYS must be a positive integer." >&2
  exit 2
fi

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

robot_id="$(
  docker exec -i \
    -e PROVISION_SERIAL="$serial_number" \
    -e PROVISION_MODEL="$model_name" \
    -e PROVISION_FIRMWARE="$firmware_version" \
    -e PROVISION_QR_HASH="$qr_token_hash" \
    -e PROVISION_QR_EXPIRES_DAYS="$qr_expires_days" \
    "$postgres_container" \
    sh -c '
      psql -X -qAt -v ON_ERROR_STOP=1 \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --set=serial="$PROVISION_SERIAL" \
        --set=model="$PROVISION_MODEL" \
        --set=firmware="$PROVISION_FIRMWARE" \
        --set=qr_hash="$PROVISION_QR_HASH" \
        --set=expires_days="$PROVISION_QR_EXPIRES_DAYS"
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
        qr_token_hash,
        qr_token_expires_at
    )
    SELECT
        id,
        :'qr_hash',
        CURRENT_TIMESTAMP + make_interval(days => :expires_days)
    FROM saved_robot
    ON CONFLICT (robot_id)
    DO UPDATE SET
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

if [[ -z "$robot_id" ]]; then
  echo "Provisioning failed: an owned robot cannot rotate an existing QR." >&2
  exit 1
fi

echo "Robot QR provisioning completed."
echo "robot_id=$robot_id"
echo "serial_number=$serial_number"
echo "qr_token=$qr_token"
echo "The raw QR token is shown only in this output. Store it securely and encode it as the QR image."
