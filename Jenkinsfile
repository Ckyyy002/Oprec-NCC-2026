pipeline {
    agent any

    environment {
        SONAR_TOKEN       = credentials('sonarqube-token')
        DISCORD_WEBHOOK   = credentials('discord-webhook-url')
        SONAR_PROJECT_KEY = 'demo-jenkins'
        PATH              = "/usr/local/go/bin:${env.PATH}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                sh 'go version'
                sh 'go build ./...'
            }
        }

        stage('Test') {
            steps {
                sh 'go test ./... -v'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh """
                        sonar-scanner \
                          -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                          -Dsonar.projectName='Demo Jenkins' \
                          -Dsonar.sources=. \
                          -Dsonar.exclusions=**/*_test.go \
                          -Dsonar.host.url=http://20.205.129.74:9000 \
                          -Dsonar.token=${SONAR_TOKEN}
                    """
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Deploy') {
            when { branch 'main' }
            steps {
                sh 'go build -o app ./...'
                echo 'Deploy berhasil.'
            }
        }
    }

    post {
        success {
            script {
                sh """curl -s -X POST '${DISCORD_WEBHOOK}' \
                  -H 'Content-Type: application/json' \
                  -d '{"embeds":[{"title":"Build Berhasil","description":"**Job:** ${env.JOB_NAME}\\n**Build:** #${env.BUILD_NUMBER}\\n**URL:** ${env.BUILD_URL}","color":3066993}]}'"""
            }
        }
        failure {
            script {
                sh """curl -s -X POST '${DISCORD_WEBHOOK}' \
                  -H 'Content-Type: application/json' \
                  -d '{"embeds":[{"title":"Build Gagal","description":"**Job:** ${env.JOB_NAME}\\n**Build:** #${env.BUILD_NUMBER}\\n**URL:** ${env.BUILD_URL}","color":15158332}]}'"""
            }
        }
        always {
            cleanWs()
        }
    }
}
