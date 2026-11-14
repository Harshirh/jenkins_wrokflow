pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    triggers {
        githubPush()
    }

    environment {
        IMAGE_REPO = 'harshithreddy382/ecommerce-app'
        KUBECONFIG = 'C:/ProgramData/Jenkins/.kube/config'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_COMMIT.take(7)}"
                }
                bat 'git status --short'
            }
        }

        stage('Build') {
            steps {
                bat 'docker build --pull -t %IMAGE_REPO%:%IMAGE_TAG% -t %IMAGE_REPO%:latest .'
            }
        }

        stage('Test') {
            steps {
                bat '''@echo off
set CONTAINER_NAME=ecommerce-ci-test-%BUILD_NUMBER%
docker run -d --name %CONTAINER_NAME% -p 18080:80 %IMAGE_REPO%:%IMAGE_TAG%
if errorlevel 1 exit /b 1
timeout /t 3 /nobreak >NUL
for %%P in ( index.html product.html productdetail.html cart.html Account.html style.css images/logo.png images/product-1.jpg ) do (
  curl.exe --fail --silent --show-error http://localhost:18080/%%P -o NUL
  if errorlevel 1 goto test_failed
)
docker rm -f %CONTAINER_NAME%
if errorlevel 1 exit /b 1
exit /b 0
:test_failed
docker logs %CONTAINER_NAME%
docker rm -f %CONTAINER_NAME%
exit /b 1'''
            }
        }

        stage('Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_PASSWORD')]) {
                    script {
                        try {
                            bat 'echo %DOCKERHUB_PASSWORD%| docker login --username %DOCKERHUB_USERNAME% --password-stdin'
                            bat 'docker push %IMAGE_REPO%:%IMAGE_TAG%'
                            bat 'docker push %IMAGE_REPO%:latest'
                        } finally {
                            bat 'docker logout'
                        }
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                bat '''@echo off
for /f "usebackq delims=" %%C in (`kubectl config current-context`) do set KUBE_CONTEXT=%%C
if not "%KUBE_CONTEXT%"=="docker-desktop" (
  echo Expected Kubernetes context docker-desktop, found %KUBE_CONTEXT%.
  exit /b 1
)
kubectl apply -f k8s/deployment.yaml
if errorlevel 1 exit /b 1
kubectl apply -f k8s/service.yaml
if errorlevel 1 exit /b 1
kubectl set image deployment/ecommerce-app ecommerce-app=%IMAGE_REPO%:%IMAGE_TAG%
if errorlevel 1 exit /b 1'''
            }
        }

        stage('Verify') {
            steps {
                bat 'kubectl rollout status deployment/ecommerce-app --timeout=180s'
                bat 'kubectl get pods -l app=ecommerce-app -o wide'
                bat 'kubectl get service ecommerce-app'
            }
        }
    }

    post {
        always {
            echo 'Pipeline finished.'
        }
    }
}
