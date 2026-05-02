# CI/CD Pipeline — Jenkins + SonarQube + Discord

> **Oprec NCC Laboratory 2026 – Pertemuan 2**

> Nama: Lucky Himawan Prasetya

> NRP: 5025241147

---

## Arsitektur

```
Developer → git push → GitHub Webhook
                              ↓
                       Jenkins :8080
                    ┌─────────────────┐
                    │ Checkout        │
                    │ Build (Go)      │
                    │ Test            │
                    │ SonarQube Scan  │
                    │ Quality Gate    │
                    │ Deploy          │
                    └────────┬────────┘
                             ↓
                    SonarQube :9000        Discord Webhook
                    (Code Analysis)   →   (Notifikasi)
```

| Service | URL |
|---------|-----|
| Jenkins | [Link](http://20.205.129.74:8080) |
| SonarQube | [Link](http://20.205.129.74:8080) |

---

## Prasyarat

- VPS Azure — Ubuntu 24.04, IP `20.205.129.74`
- Port terbuka di Azure NSG: `22`, `8080`, `9000`, `50000`
- Akun GitHub + Personal Access Token
- Server Discord + Webhook URL

---

## 1. Persiapan VPS

### Buka Port di Azure NSG

**Azure Portal** → Virtual Machine → **Networking** → **Add inbound port rule**

Tambahkan port: `8080`, `9000`, `50000` (TCP)

### SSH & Update Sistem

```bash
ssh azureuser@20.205.129.74
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git
```

---

## 2. Instalasi Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker
```

---

## 3. Instalasi Jenkins

### Buat Docker Network

```bash
docker network create jenkins
```

### Jalankan Docker-in-Docker

```bash
docker run \
  --name jenkins-docker \
  --rm --detach --privileged \
  --network jenkins \
  --network-alias docker \
  --env DOCKER_TLS_CERTDIR=/certs \
  --volume jenkins-docker-certs:/certs/client \
  --volume jenkins-data:/var/jenkins_home \
  --publish 2376:2376 \
  docker:dind --storage-driver overlay2
```

### Buat Dockerfile Jenkins

```bash
mkdir ~/jenkins && cd ~/jenkins
```

Buat file `Dockerfile`:

```dockerfile
FROM jenkins/jenkins:2.541.3-jdk21
USER root

RUN apt-get update && apt-get install -y lsb-release ca-certificates curl unzip && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y docker-ce-cli && \
    curl -fsSL https://go.dev/dl/go1.22.3.linux-amd64.tar.gz -o /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz && \
    curl -fsSL https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-6.2.1.4610-linux-x64.zip \
      -o /tmp/sonar.zip && \
    unzip /tmp/sonar.zip -d /opt && \
    mv /opt/sonar-scanner-6.2.1.4610-linux-x64 /opt/sonar-scanner && \
    rm /tmp/sonar.zip && \
    chmod +x /opt/sonar-scanner/bin/sonar-scanner && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH=$PATH:/usr/local/go/bin:/opt/sonar-scanner/bin
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow json-path-api"
```

### Build & Jalankan Jenkins

```bash
docker build -t myjenkins-blueocean:2.541.3-1 .

docker run \
  --name jenkins-blueocean \
  --restart=on-failure --detach \
  --network jenkins \
  --env DOCKER_HOST=tcp://docker:2376 \
  --env DOCKER_CERT_PATH=/certs/client \
  --env DOCKER_TLS_VERIFY=1 \
  --publish 8080:8080 \
  --publish 50000:50000 \
  --volume jenkins-data:/var/jenkins_home \
  --volume jenkins-docker-certs:/certs/client:ro \
  myjenkins-blueocean:2.541.3-1
```

### Setup Awal Jenkins

```bash
docker exec jenkins-blueocean cat /var/jenkins_home/secrets/initialAdminPassword
```
```
docker logs <container id jenkins>
```

1. Buka `http://20.205.129.74:8080`
2. Masukkan password di atas
3. Pilih **Install suggested plugins**
4. Buat akun admin

---

## 4. Instalasi SonarQube

```bash
docker volume create sonarqube_data
docker volume create sonarqube_logs
docker volume create sonarqube_extensions

docker run -d \
  --name sonarqube \
  --restart=on-failure \
  -p 9000:9000 \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  -v sonarqube_logs:/opt/sonarqube/logs \
  sonarqube:lts-community
```

Buka `http://20.205.129.74:9000` 

---

## 5. Konfigurasi Jenkins

### Install Plugin

**Manage Jenkins** → **Plugins** → **Available plugins**, install:

- `SonarQube Scanner`
- `GitHub Integration`
- `Pipeline`

---

## 6. Integrasi Jenkins & SonarQube

### Generate Token di SonarQube

**SonarQube** → avatar → **My Account** → **Security** → **Generate Token**:
- Name: `jenkins-token`, Type: `Global Analysis Token` → salin token

### Tambah Credential di Jenkins

**Manage Jenkins** → **Credentials** → **Global** → **Add Credentials**:

| Field | Value |
|-------|-------|
| Kind | Secret text |
| Secret | `<token SonarQube>` |
| ID | `sonarqube-token` |

### Konfigurasi SonarQube Server

**Manage Jenkins** → **System** → **SonarQube servers** → **Add**:

| Field | Value |
|-------|-------|
| Name | `sonarqube` |
| Server URL | `http://20.205.129.74:9000` |
| Server authentication token | `sonarqube-token` |

> Nama harus sama persis dengan yang digunakan di Jenkinsfile (`withSonarQubeEnv('sonarqube')`).

### Buat Webhook SonarQube → Jenkins

**SonarQube** → **Administration** → **Webhooks** → **Create**:

| Field | Value |
|-------|-------|
| Name | `Jenkins` |
| URL | `http://20.205.129.74:8080/sonarqube-webhook/` |

> Webhook ini wajib ada agar stage **Quality Gate** tidak timeout. Jenkins menunggu callback dari SonarQube melalui URL ini setelah analisis selesai.

---

## 7. Integrasi Jenkins & GitHub

### Generate GitHub Personal Access Token

**GitHub** → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token**:
- Scope: `repo`, `admin:repo_hook`
- Salin token yang muncul

### Tambah Credential GitHub di Jenkins

**Manage Jenkins** → **Credentials** → **Global** → **Add Credentials**:

| Field | Value |
|-------|-------|
| Kind | Secret text |
| Secret | `<GitHub token>` |
| ID | `github-credentials` |

### Konfigurasi GitHub Server di Jenkins

**Manage Jenkins** → **System** → **GitHub** → **Add GitHub Server**:
- Name: `GitHub`
- Credentials: `github-credentials`
- Klik **Test connection** — pastikan berhasil

### Tambah Webhook di GitHub Repository

**Repository** → **Settings** → **Webhooks** → **Add webhook**:

| Field | Value |
|-------|-------|
| Payload URL | `http://20.205.129.74:8080/github-webhook/` |
| Content type | `application/json` |
| Events | Just the push event |

---

## 8. Discord Webhook

### Buat Webhook di Discord

**Discord** → Channel Settings → **Integrations** → **Webhooks** → **New Webhook** → salin URL.

### Simpan sebagai Credential Jenkins

**Manage Jenkins** → **Credentials** → **Global** → **Add Credentials**:

| Field | Value |
|-------|-------|
| Kind | Secret text |
| Secret | `<Discord Webhook URL>` |
| ID | `discord-webhook-url` |

---

## 9. Jenkinsfile

```groovy
pipeline {
    agent any

    environment {
        SONAR_TOKEN       = credentials('sonarqube-token')
        DISCORD_WEBHOOK   = credentials('discord-webhook-url')
        SONAR_PROJECT_KEY = 'demo-jenkins'
        PATH              = "/usr/local/go/bin:/opt/sonar-scanner/bin:${env.PATH}"
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
```

---

## 10. Membuat Job di Jenkins

1. **New Item** → nama: `demo-jenkins-pipeline` → pilih **Pipeline** → **OK**
2. Konfigurasi:

**General:**
- ✅ GitHub project → URL: `https://github.com/<username>/demo-jenkins/`

**Build Triggers:**
- ✅ GitHub hook trigger for GIT SCM Polling

**Pipeline:**
- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: `https://github.com/<username>/demo-jenkins.git`
- Credentials: `github-credentials`
- Branch: `*/main`
- Script Path: `Jenkinsfile`

3. Klik **Save** → **Build Now** untuk build pertama.

---

## Hasil & Bukti

### 1. Jenkins — Stage View

Screenshot halaman job `demo-jenkins-pipeline` yang menampilkan **Stage View** dengan semua stage berwarna hijau.

> Lokasi: [http://20.205.129.74:8080/job/demo-jenkins-pipeline/](http://20.205.129.74:8080/job/demo-jenkins-pipeline/)

<img width="1534" height="125" alt="image" src="https://github.com/user-attachments/assets/d9fd97ad-710b-452f-8e15-851371529c8e" />

<img width="1309" height="371" alt="screenshot-2026-05-02_11 39 14" src="https://github.com/user-attachments/assets/4905081c-bef3-484c-afb2-8478a9b2461c" />

---

### 2. Jenkins — Console Output Build Berhasil

Screenshot Console Output dari build terakhir yang menunjukkan log tiap stage berjalan sukses dan diakhiri dengan `Finished: SUCCESS`.

> Lokasi: [http://20.205.129.74:8080/job/demo-jenkins-pipeline/17/console](http://20.205.129.74:8080/job/demo-jenkins-pipeline/17/console)

[File Console Output](https://github.com/Ckyyy002/Oprec-NCC-2026/blob/module-2/%2317.txt)

---

### 3. Jenkins — Daftar Credentials

Screenshot halaman Credentials yang menampilkan ketiga credential yang terdaftar: `sonarqube-token`, `github-credentials`, dan `discord-webhook-url`.

> Lokasi: **Manage Jenkins → Credentials → System → Global credentials**

<img width="1610" height="364" alt="image" src="https://github.com/user-attachments/assets/72947758-fcab-4d06-8363-b5f4d82f05dd" />

---

### 4. Jenkins — Konfigurasi SonarQube Server

Screenshot halaman System Configuration bagian SonarQube servers yang menampilkan nama server `sonarqube` dan URL [http://20.205.129.74:9000](http://20.205.129.74:9000).

> Lokasi: **Manage Jenkins → System → SonarQube servers**

<img width="1579" height="704" alt="image" src="https://github.com/user-attachments/assets/22f416ae-d8b0-4674-9e90-117efb3aa45e" />

---

### 5. GitHub — Webhook Aktif

Screenshot halaman Webhooks repository GitHub yang menampilkan webhook dengan Payload URL [http://20.205.129.74:8080/github-webhook/](http://20.205.129.74:8080/github-webhook/).

> Lokasi: Repository GitHub → **Settings → Webhooks**

<img width="868" height="225" alt="image" src="https://github.com/user-attachments/assets/20be5745-444c-409e-8b88-d8f5c5effb70" />

---

### 6. SonarQube — Hasil Analisis Kode

Screenshot halaman project di SonarQube yang menampilkan hasil analisis: jumlah Bugs, Vulnerabilities, Security Hotspots, Code Smells, Coverage, dan Duplications.

> Lokasi: [http://20.205.129.74:9000/projects](http://20.205.129.74:9000/projects)

<img width="997" height="173" alt="image" src="https://github.com/user-attachments/assets/55b01e45-1253-4042-9db0-7e6a42bac73e" />

---

### 7. Discord — Notifikasi Build Berhasil

Screenshot channel Discord yang menampilkan embed notifikasi berwarna hijau bertuliskan **Build Berhasil** beserta informasi Job, Build number, dan URL.

<img width="496" height="163" alt="image" src="https://github.com/user-attachments/assets/b5d833fa-b898-413b-ae44-c66e42d54b81" />

---

## Kendala & Solusi

### 1. Jenkins tidak bisa start setelah VM di-restart

<img width="1854" height="113" alt="screenshot-2026-05-02_10 52 45" src="https://github.com/user-attachments/assets/27b94095-6090-4b38-af81-1cb85fcdebb5" />

**Gejala:** `exec: java: not found` di logs Jenkins.

**Penyebab:** Flag `--env PATH=...` saat `docker run` menimpa PATH default container sehingga Java tidak ditemukan.

**Solusi:** Hapus flag `--env PATH=...` dari perintah `docker run`. PATH untuk Go dan sonar-scanner sudah di-set di dalam Dockerfile via `ENV`, tidak perlu di-override dari luar.


```bash
docker run \
  --name jenkins-docker \
  --rm --detach --privileged \
  --network jenkins \
  --network-alias docker \
  --env DOCKER_TLS_CERTDIR=/certs \
  --volume jenkins-docker-certs:/certs/client \
  --volume jenkins-data:/var/jenkins_home \
  --publish 2376:2376 \
  docker:dind --storage-driver overlay2

docker start jenkins-blueocean
```

---

### 2. `npm: not found` saat stage Build

**Penyebab:** Repository demo-jenkins adalah project Go, bukan Node.js. Jenkinsfile awal menggunakan `npm install` yang tidak sesuai.

**Solusi:** Ganti stage Build dan Test di Jenkinsfile menggunakan perintah Go:

```groovy
stage('Build') {
    steps {
        sh 'go build ./...'
    }
}
stage('Test') {
    steps {
        sh 'go test ./... -v'
    }
}
```

---

## Referensi

- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [SonarQube Documentation](https://docs.sonarsource.com/)
- [Materi Oprec](https://github.com/ncclaboratory18/Oprec_2026_Pertemuan_2)
- [Repository Demo](https://github.com/hamasfaa/demo-jenkins)
