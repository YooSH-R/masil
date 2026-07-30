#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
DEPLOYMENT="${JENKINS_DEPLOYMENT:-jenkins}"
SECRET_NAME="${JENKINS_WEBHOOK_SECRET_NAME:-jenkins-webhook-secret}"
SECRET_KEY="GITLAB_WEBHOOK_TOKEN"

if kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" >/dev/null 2>&1; then
  echo "Reusing existing ${SECRET_NAME}; the webhook token was not rotated."
elif [[ -n "${GITLAB_WEBHOOK_TOKEN:-}" ]]; then
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal="${SECRET_KEY}=${GITLAB_WEBHOOK_TOKEN}"
  echo "Created ${SECRET_NAME} from the supplied environment variable."
else
  GITLAB_WEBHOOK_TOKEN="$(openssl rand -hex 32)"
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal="${SECRET_KEY}=${GITLAB_WEBHOOK_TOKEN}"
  unset GITLAB_WEBHOOK_TOKEN
  echo "Created ${SECRET_NAME} with a cryptographically random token."
fi

kubectl -n "${NAMESPACE}" set env "deployment/${DEPLOYMENT}" \
  --from="secret/${SECRET_NAME}"

kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" \
  --timeout=180s

echo "Jenkins webhook secret was applied."
echo "Set the same token in the GitLab webhook, then run the Jenkins job once."
