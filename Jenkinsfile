pipeline {
    agent any

    options {
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        KUBECTL_VERSION = 'v1.36.2'
        K8S_NAMESPACE = 's15a203-dev'
    }

    stages {
        stage('Git Clone') {
            steps {
                script {
                    git(
                        branch: 'dev',
                        credentialsId: 'gitlab-access-token',
                        url: 'https://lab.ssafy.com/s15-webmobile3-sub1/S15P11A203.git'
                    )
                    env.GIT_COMMIT = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()
                }
            }
        }

        stage('Prepare') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DOCKERHUB_USERNAME',
                        passwordVariable: 'DOCKERHUB_TOKEN'
                    )
                ]) {
                    script {
                        env.BACKEND_IMAGE = "${env.DOCKERHUB_USERNAME}/s15a203-backend:${env.GIT_COMMIT.take(8)}"
                    }
                }

                sh '''
                    mkdir -p .tools
                    curl -fsSLo .tools/kubectl \
                      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
                    chmod +x .tools/kubectl
                '''
            }
        }

        stage('Backend Test') {
            steps {
                dir('02_Backend') {
                    sh 'chmod +x gradlew'
                    sh './gradlew test'
                }
            }
        }

        stage('Build and Push Image') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DOCKERHUB_USERNAME',
                        passwordVariable: 'DOCKERHUB_TOKEN'
                    )
                ]) {
                    dir('02_Backend') {
                        sh '''
                            set +x
                            ./gradlew jib \
                              --image="$BACKEND_IMAGE" \
                              -Djib.to.auth.username="$DOCKERHUB_USERNAME" \
                              -Djib.to.auth.password="$DOCKERHUB_TOKEN"
                        '''
                    }
                }
            }
        }

        stage('Deploy to AWS k3s') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub',
                        usernameVariable: 'DOCKERHUB_USERNAME',
                        passwordVariable: 'DOCKERHUB_TOKEN'
                    )
                ]) {
                    sh '''
                        set +x

                        .tools/kubectl -n "$K8S_NAMESPACE" create secret docker-registry dockerhub-registry \
                          --docker-server="https://index.docker.io/v1/" \
                          --docker-username="$DOCKERHUB_USERNAME" \
                          --docker-password="$DOCKERHUB_TOKEN" \
                          --dry-run=client -o yaml \
                          | .tools/kubectl apply -f -

                        sed "s|__BACKEND_IMAGE__|$BACKEND_IMAGE|g" k8s/dev/deployment.yaml \
                          | .tools/kubectl -n "$K8S_NAMESPACE" apply -f -

                        .tools/kubectl -n "$K8S_NAMESPACE" apply \
                          -f k8s/dev/service.yaml \
                          -f k8s/dev/ingress.yaml

                        .tools/kubectl -n "$K8S_NAMESPACE" rollout status \
                          deployment/backend --timeout=180s
                    '''
                }
            }
        }

        stage('Verify') {
            steps {
                sh '''
                    .tools/kubectl -n "$K8S_NAMESPACE" get deployment backend
                    .tools/kubectl -n "$K8S_NAMESPACE" get pods -l app=backend -o wide
                    .tools/kubectl -n "$K8S_NAMESPACE" get service backend
                    .tools/kubectl -n "$K8S_NAMESPACE" get ingress backend
                '''
            }
        }
    }

    post {
        success {
            echo "AWS k3s development deployment succeeded: ${env.BACKEND_IMAGE}"
        }
        failure {
            echo 'Backend build or AWS k3s deployment failed.'
        }
    }
}
