# 🔧 Jenkins & SonarQube — CI/CD dengan Code Quality Gate

## Overview

| Tool | Peran |
|---|---|
| **Jenkins** | Automation server untuk CI/CD pipeline |
| **SonarQube** | Platform analisis kualitas dan keamanan kode |

Keduanya bekerja bersama: Jenkins menjalankan build/test, kemudian memanggil SonarQube untuk analisis kode. Pipeline hanya dilanjutkan jika **Quality Gate** lulus.

---

## Jenkins

### Apa itu Jenkins?

Jenkins adalah server otomasi open-source yang membantu mengotomatiskan bagian-bagian dalam pengembangan software — build, test, deploy — mendukung **Continuous Integration** dan **Continuous Delivery**.

### Instalasi via Docker

```yaml
# docker-compose.yml
version: '3.9'

services:
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: jenkins
    user: root
    ports:
      - "8080:8080"
      - "50000:50000"
    volumes:
      - jenkins_home:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

volumes:
  jenkins_home:
```

```bash
docker compose up -d

# Ambil initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

---

### Jenkinsfile (Declarative Pipeline)

```groovy
pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'myapp'
        DOCKER_TAG   = "${env.BUILD_NUMBER}"
        SONAR_TOKEN  = credentials('sonar-token')
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                echo "Branch: ${env.GIT_BRANCH}"
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'npm ci'
            }
        }

        stage('Unit Test') {
            steps {
                sh 'npm test -- --coverage'
            }
            post {
                always {
                    junit 'coverage/junit.xml'
                    publishHTML([
                        reportDir: 'coverage/lcov-report',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        sonar-scanner \
                          -Dsonar.projectKey=myapp \
                          -Dsonar.sources=src \
                          -Dsonar.tests=tests \
                          -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
                          -Dsonar.token=${SONAR_TOKEN}
                    '''
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

        stage('Build Docker Image') {
            steps {
                sh "docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                sh "docker compose up -d --build"
            }
        }
    }

    post {
        success {
            echo '✅ Pipeline berhasil!'
            discordSend(
                webhookURL: credentials('discord-webhook'),
                message: "✅ Build #${BUILD_NUMBER} sukses — ${env.JOB_NAME}"
            )
        }
        failure {
            echo '❌ Pipeline gagal!'
            discordSend(
                webhookURL: credentials('discord-webhook'),
                message: "❌ Build #${BUILD_NUMBER} GAGAL — ${env.JOB_NAME}"
            )
        }
        always {
            cleanWs()
        }
    }
}
```

---

### Konfigurasi Jenkins

#### Plugin yang Disarankan

| Plugin | Fungsi |
|---|---|
| `Pipeline` | Mendukung Jenkinsfile |
| `Git` | Integrasi dengan repository Git |
| `SonarQube Scanner` | Koneksi ke SonarQube |
| `Docker Pipeline` | Build & push Docker image |
| `Discord Notifier` | Notifikasi ke Discord |
| `Email Extension` | Notifikasi email |
| `Blue Ocean` | UI modern untuk pipeline |

#### Credentials Setup

```
Manage Jenkins → Credentials → Global → Add Credential

Jenis credential:
- Secret Text → untuk token (SonarQube, Discord webhook)
- Username/Password → untuk Docker registry
- SSH Key → untuk deploy ke server
```

---

## SonarQube

### Apa itu SonarQube?

SonarQube adalah platform untuk **inspeksi kontinu kualitas kode** — mendeteksi bug, code smell, vulnerability, dan security hotspot secara otomatis.

### Instalasi via Docker

```yaml
# docker-compose.yml (tambahkan ke stack yang ada)
version: '3.9'

services:
  sonarqube:
    image: sonarqube:community
    container_name: sonarqube
    depends_on:
      sonar-db:
        condition: service_healthy
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://sonar-db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar
    ports:
      - "9000:9000"
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_extensions:/opt/sonarqube/extensions
    restart: unless-stopped

  sonar-db:
    image: postgres:15-alpine
    container_name: sonar-db
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar
      POSTGRES_DB: sonar
    volumes:
      - sonar_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sonar"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  sonarqube_data:
  sonarqube_logs:
  sonarqube_extensions:
  sonar_pgdata:
```

> **Catatan sistem:** SonarQube membutuhkan `vm.max_map_count` minimal 524288.
> Jalankan: `sudo sysctl -w vm.max_map_count=524288`

---

### Konfigurasi `sonar-project.properties`

```properties
# Identitas proyek
sonar.projectKey=myapp
sonar.projectName=My Application
sonar.projectVersion=1.0

# Source & test
sonar.sources=src
sonar.tests=tests
sonar.exclusions=**/node_modules/**,**/*.test.ts,**/dist/**

# Coverage
sonar.javascript.lcov.reportPaths=coverage/lcov.info
sonar.testExecutionReportPaths=coverage/test-reporter.xml

# Language
sonar.language=ts
sonar.typescript.tsconfigPath=tsconfig.json

# Server
sonar.host.url=http://sonarqube:9000
```

---

### Quality Gate

Quality Gate adalah sekumpulan kondisi yang harus dipenuhi agar kode dianggap layak.

#### Kondisi Default (Sonar Way)

| Metrik | Threshold |
|---|---|
| Coverage on New Code | ≥ 80% |
| Duplicated Lines on New Code | ≤ 3% |
| Maintainability Rating | A |
| Reliability Rating | A |
| Security Rating | A |
| Security Hotspots Reviewed | 100% |

#### Custom Quality Gate

```
SonarQube → Quality Gates → Create

Tambah kondisi custom, misalnya:
- Cognitive Complexity ≤ 15 per function
- No new Critical/Blocker issues
```

---

### Kategori Temuan SonarQube

```
Bug         → Kode yang berpotensi menghasilkan perilaku salah saat runtime
Vulnerability → Celah keamanan yang bisa dieksploitasi
Code Smell  → Masalah maintainability (duplikasi, kompleksitas tinggi, dll)
Security Hotspot → Area yang perlu direview secara manual
```

#### Contoh Issue dan Solusinya

```typescript
// ❌ Code Smell: Cognitive Complexity terlalu tinggi
function processData(data: any[]) {
    for (let i = 0; i < data.length; i++) {
        if (data[i]) {
            if (data[i].active) {
                if (data[i].value > 0) {
                    // ...nested terlalu dalam
                }
            }
        }
    }
}

// ✅ Refactor: Extract functions, early return
function processData(data: Item[]) {
    data.filter(isValidItem).forEach(processItem);
}

function isValidItem(item: Item): boolean {
    return item?.active && item.value > 0;
}
```

---

## Integrasi Jenkins ↔ SonarQube

### Setup di Jenkins

```
1. Manage Jenkins → Configure System
2. SonarQube Servers → Add SonarQube
   - Name: SonarQube
   - Server URL: http://sonarqube:9000
   - Server authentication token: [pilih credential]

3. Manage Jenkins → Global Tool Configuration
4. SonarQube Scanner → Add Scanner
   - Name: SonarScanner
   - Install automatically: ✅
```

### Alur Kerja

```
Git Push
   │
   ▼
Jenkins Trigger (Webhook)
   │
   ▼
Build & Test
   │
   ▼
SonarQube Analysis ──► SonarQube Server
   │                        │
   ▼                        ▼
Wait for Quality Gate ◄── Hasil Analisis
   │
   ├── PASSED → Deploy
   └── FAILED → Abort Pipeline + Notifikasi
```

---

## Troubleshooting

| Masalah | Solusi |
|---|---|
| Quality Gate stuck "In Progress" | Pastikan webhook SonarQube → Jenkins dikonfigurasi |
| SonarQube OOM | Tambah heap: `SONAR_WEB_JAVAOPTS=-Xmx2g` |
| Jenkins tidak bisa koneksi ke SonarQube | Gunakan nama service Docker, bukan `localhost` |
| Coverage 0% di SonarQube | Pastikan path `lcov.info` benar di `sonar-project.properties` |

---

## Referensi

- [Jenkins Docs](https://www.jenkins.io/doc/)
- [SonarQube Docs](https://docs.sonarsource.com/sonarqube/)
- [SonarQube Scanner for Jenkins](https://docs.sonarsource.com/sonarqube/latest/analyzing-source-code/scanners/jenkins-extension-sonarqube/)
