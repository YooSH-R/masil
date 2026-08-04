#!/usr/bin/env sh
set -eu

: "${K8S_NAMESPACE:?K8S_NAMESPACE is required}"

KUBECTL_BIN="${KUBECTL_BIN:-.tools/kubectl}"

if [ "$#" -eq 0 ]; then
  echo "At least one migration file is required." >&2
  exit 1
fi

"$KUBECTL_BIN" -n "$K8S_NAMESPACE" wait \
  --for=condition=Ready pod/postgres-0 \
  --timeout=120s

for migration_file in "$@"; do
  if [ ! -f "$migration_file" ]; then
    echo "Migration file not found: $migration_file" >&2
    exit 1
  fi

  echo "Applying database migration: $migration_file"
  "$KUBECTL_BIN" -n "$K8S_NAMESPACE" exec -i postgres-0 -- \
    sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    < "$migration_file"
done
