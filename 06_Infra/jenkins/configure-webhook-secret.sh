#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
DEPLOYMENT="${JENKINS_DEPLOYMENT:-jenkins}"
SECRET_NAME="${JENKINS_WEBHOOK_SECRET_NAME:-jenkins-webhook-secret}"
SECRET_KEY="GITLAB_WEBHOOK_TOKEN"

if [[ -z "${GITLAB_WEBHOOK_TOKEN:-}" ]]; then
  read -r -s -p "GitLab webhook secret token: " GITLAB_WEBHOOK_TOKEN
  printf '\n'
fi

if [[ -z "${GITLAB_WEBHOOK_TOKEN}" ]]; then
  echo "Webhook token must not be empty." >&2
  exit 1
fi

kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
  --from-literal="${SECRET_KEY}=${GITLAB_WEBHOOK_TOKEN}" \
  --dry-run=client \
  -o yaml \
  | kubectl apply -f -

kubectl -n "${NAMESPACE}" set env "deployment/${DEPLOYMENT}" \
  --from="secret/${SECRET_NAME}"

kubectl -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" \
  --timeout=180s

echo "Jenkins webhook secret was applied."
echo "Set the same token in the GitLab webhook, then run the Jenkins job once."
