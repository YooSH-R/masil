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

The script reads the token without echoing it, stores it in the
`jenkins-webhook-secret` Kubernetes Secret, injects that Secret into the
Jenkins Deployment, and waits for the rollout.

After applying it:

1. Set the same value in the GitLab project webhook's **Secret token** field.
2. Run `dev-backend-api` manually once so Jenkins applies the trigger.
3. Test a GitLab push event.

Do not print the Secret with `kubectl get secret ... -o yaml` or commit a
decoded value. Protect changes to `06_Infra/Jenkinsfile` with merge request
approval because pipeline code runs with access to the Jenkins environment.
