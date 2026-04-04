// Jenkinsfile — Manga Hub CI/CD pipeline
// Repo: https://github.com/traliach/React_Web_Application_Project
//
// Stages:
//   1. Checkout   — clone the repo
//   2. Build      — npm ci + npm run build (validates the app compiles)
//   3. Docker     — build image with build number tag
//   4. Push       — push to GHCR (ghcr.io/traliach/manga-hub)
//   5. Deploy     — update docker-compose on EC2 via Ansible

pipeline {
    agent any

    environment {
        REGISTRY      = 'ghcr.io'
        IMAGE_NAME    = 'ghcr.io/traliach/manga-hub'
        IMAGE_TAG     = "${BUILD_NUMBER}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            // Validates the app compiles — catches TypeScript errors and broken imports
            agent {
                docker {
                    image 'node:20-alpine'
                    reuseNode true
                }
            }
            steps {
                sh 'npm ci'
                sh 'npm run build'
            }
        }

        stage('Docker Build') {
            steps {
                script {
                    dockerImage = docker.build("${IMAGE_NAME}:${IMAGE_TAG}")
                }
            }
        }

        stage('Push to GHCR') {
            steps {
                script {
                    // 'ghcr-credentials' is the credential ID set in JCasC (jenkins.yaml)
                    docker.withRegistry("https://${REGISTRY}", 'ghcr-credentials') {
                        dockerImage.push("${IMAGE_TAG}")
                        dockerImage.push("latest")
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                // Tell EC2 to pull the new image and restart the manga-hub container
                withCredentials([usernamePassword(
                    credentialsId: 'ghcr-credentials',
                    usernameVariable: 'GHCR_USER',
                    passwordVariable: 'GHCR_PASS'
                )]) {
                    sh """
                        aws ssm send-command \
                          --instance-ids i-0eb277f732ee785ac \
                          --document-name AWS-RunShellScript \
                          --region us-east-1 \
                          --parameters 'commands=[
                            "echo ${GHCR_PASS} | docker login ghcr.io -u ${GHCR_USER} --password-stdin",
                            "cd /opt/platform && APP_VERSION=${IMAGE_TAG} docker compose pull manga-hub",
                            "cd /opt/platform && APP_VERSION=${IMAGE_TAG} docker compose up -d manga-hub --remove-orphans"
                          ]'
                    """
                }
            }
        }
    }

    post {
        success {
            echo "Manga Hub ${IMAGE_TAG} deployed successfully."
        }
        failure {
            echo "Pipeline failed. Check the logs above."
        }
        always {
            // Clean up local Docker image to avoid disk fill on the Jenkins host
            sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true"
        }
    }
}
