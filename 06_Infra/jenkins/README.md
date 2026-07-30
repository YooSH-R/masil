# Jenkins GitLab webhook token

The GitLab webhook token must not be committed to this repository. Jenkins
reads it from the `GITLAB_WEBHOOK_TOKEN` controller environment variable.

## Apply or rotate the token

Run this on the k3s server:

```bash
cd 06_Infra/jenkins
chmod +x configure-webhook-secret.sh
./configure-webhook-secret.sh
```

If the Secret does not exist, the script generates a cryptographically random
64-character token inside the k3s server. If it already exists, the same token
is reused so rerunning the script does not break the webhook. A token supplied
through the `GITLAB_WEBHOOK_TOKEN` environment variable is only used when the
Secret is first created.

The token is stored in the `jenkins-webhook-secret` Kubernetes Secret. The
script maps only its `GITLAB_WEBHOOK_TOKEN` key into the Jenkins Deployment and
waits for the rollout.

After applying it:

1. Set the same value in the GitLab project webhook's **Secret token** field.
2. Run `dev-backend-api` manually once so Jenkins applies the trigger.
3. Test a GitLab push event.

To copy the generated token into the GitLab webhook, reveal it only in a
trusted administrator terminal:

```bash
kubectl -n jenkins get secret jenkins-webhook-secret \
  -o jsonpath='{.data.GITLAB_WEBHOOK_TOKEN}' | base64 -d
printf '\n'
```

Do not print the Secret with `kubectl get secret ... -o yaml` or commit a
decoded value. Protect changes to `06_Infra/Jenkinsfile` with merge request
approval because pipeline code runs with access to the Jenkins environment.
