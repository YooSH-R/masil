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

1. Add one GitLab project webhook for each Jenkins job and set the same value
   in both webhooks' **Secret token** field.
2. Create the two Jenkins Pipeline jobs described below.
3. Run both jobs manually once so Jenkins applies their GitLab triggers.
4. Test GitLab push events for `dev` and `master`.

## Split dev and prod jobs

Create two **Pipeline script from SCM** jobs that use the same repository:

| Jenkins job | Branch | Script Path | Kubernetes namespace |
| --- | --- | --- | --- |
| `dev-backend-api` | `dev` | `06_Infra/Jenkinsfile.dev` | `s15a203-dev` |
| `prod-backend-api` | `master` | `06_Infra/Jenkinsfile.prod` | `s15a203-prod` |

Copy each job's GitLab webhook URL from Jenkins into a separate GitLab
webhook. Both webhooks may use the same secret token because branch filters in
the two Jenkinsfiles restrict which job can deploy each branch.

The development job deploys automatically when `02_Backend/` changes on
`dev`. Its public API prefix is `/dev/api/v1`.

The production job builds from `master`, waits for a Jenkins user to approve
the `Approve Production` stage, and then updates the production Deployment.
Its public API prefix remains `/api/v1`.

Do not configure either job to load the other environment's Jenkinsfile.
Branch validation inside each pipeline stops an incorrectly configured job
before it can deploy.

To copy the generated token into the GitLab webhook, reveal it only in a
trusted administrator terminal:

```bash
kubectl -n jenkins get secret jenkins-webhook-secret \
  -o jsonpath='{.data.GITLAB_WEBHOOK_TOKEN}' | base64 -d
printf '\n'
```

Do not print the Secret with `kubectl get secret ... -o yaml` or commit a
decoded value. Protect changes to `06_Infra/Jenkinsfile.dev` and
`06_Infra/Jenkinsfile.prod` with merge request approval because pipeline code
runs with access to the Jenkins environment.
