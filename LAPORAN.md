# CI/CD Pipeline — Jenkins + SonarQube + Discord

> **Oprec NCC Laboratory 2026 – Pertemuan 2**

> Nama: Lucky Himawan Prasetya

> NRP: 5025241147

---

## Daftar Isi

- [Deskripsi Pipeline](#deskripsi-pipeline)
- [Arsitektur](#arsitektur)
- [Penjelasan Alur Pipeline](#penjelasan-alur-pipeline)
- [Penjelasan Integrasi Jenkins & SonarQube](#penjelasan-integrasi-jenkins--sonarqube)
- [Prasyarat](#prasyarat)
- [1. Persiapan VPS](#1-persiapan-vps)
- [2. Instalasi Docker](#2-instalasi-docker)
- [3. Instalasi Jenkins](#3-instalasi-jenkins)
- [4. Instalasi SonarQube](#4-instalasi-sonarqube)
- [5. Konfigurasi Jenkins](#5-konfigurasi-jenkins)
- [6. Integrasi Jenkins & SonarQube](#6-integrasi-jenkins--sonarqube)
- [7. Integrasi Jenkins & GitHub](#7-integrasi-jenkins--github)
- [8. Discord Webhook](#8-discord-webhook)
- [9. Jenkinsfile](#9-jenkinsfile)
- [10. Membuat Job di Jenkins](#10-membuat-job-di-jenkins)
- [Hasil & Bukti](#hasil--bukti)
- [Kendala & Solusi](#kendala--solusi)
- [Referensi](#referensi)

---

## Deskripsi Pipeline

Pipeline ini merupakan implementasi CI/CD (Continuous Integration/Continuous Deployment) untuk project Go sederhana yang di-host di GitHub dan di-deploy menggunakan Jenkins di Azure VPS.

Tujuan utama pipeline ini adalah mengotomatisasi seluruh proses dari mulai pengambilan kode, build, pengujian, hingga analisis kualitas kode — sehingga setiap kali developer melakukan `git push`, pipeline akan berjalan secara otomatis tanpa intervensi manual.

Pipeline ini mencakup fitur-fitur berikut:

- **Otomasi build dan test** menggunakan Go toolchain yang diinstall langsung di container Jenkins
- **Analisis kualitas kode** menggunakan SonarQube yang memeriksa bug, vulnerability, code smell, dan duplikasi kode
- **Quality Gate** yang akan menggagalkan pipeline secara otomatis jika kode tidak memenuhi standar kualitas minimum
- **Trigger otomatis** via GitHub Webhook setiap kali ada push ke branch `main`
- **Notifikasi real-time** ke channel Discord dengan status build berhasil atau gagal
- **Credential management** menggunakan Jenkins Credentials Manager sehingga tidak ada secret yang di-hardcode di kode

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
| Jenkins | [http://20.205.129.74:8080](http://20.205.129.74:8080) |
| SonarQube | [http://20.205.129.74:9000](http://20.205.129.74:9000) |

---

## Penjelasan Alur Pipeline

Pipeline didefinisikan sepenuhnya dalam `Jenkinsfile` menggunakan sintaks Declarative Pipeline. Berikut penjelasan tiap stage dari awal hingga akhir:

### Stage 1 — Checkout

Jenkins mengambil kode terbaru dari repository GitHub menggunakan credential yang sudah terdaftar. Stage ini berjalan otomatis saat ada push ke branch `main` melalui GitHub Webhook.

### Stage 2 — Build

Go toolchain dikompilasi menggunakan perintah `go build ./...`. Stage ini memastikan bahwa kode dapat dikompilasi tanpa error sebelum dilanjutkan ke tahap berikutnya. Jika build gagal, seluruh pipeline berhenti dan notifikasi dikirim ke Discord.

### Stage 3 — Test

Menjalankan unit test menggunakan `go test ./... -v`. Jika tidak ada test file, stage ini tetap berjalan dan dilaporkan sebagai passed. Pada implementasi yang lebih lengkap, hasil coverage dapat dikirim ke SonarQube untuk dianalisis.

### Stage 4 — SonarQube Analysis

sonar-scanner mengirimkan laporan analisis kode ke SonarQube server. SonarQube kemudian memeriksa kode berdasarkan metrik berikut:

| Metrik | Keterangan |
|--------|------------|
| Bugs | Kesalahan logika yang dapat menyebabkan program tidak berjalan benar |
| Vulnerabilities | Celah keamanan yang dapat dieksploitasi |
| Security Hotspots | Kode yang perlu direview secara manual |
| Code Smells | Kode yang buruk dari sisi maintainability |
| Duplications | Persentase kode yang duplikat |

### Stage 5 — Quality Gate

Jenkins menunggu callback dari SonarQube melalui webhook. Jika hasil analisis memenuhi semua kondisi Quality Gate (tidak ada bug baru, tidak ada vulnerability, dll), pipeline dilanjutkan. Jika gagal, pipeline dihentikan secara otomatis dengan `abortPipeline: true`.

### Stage 6 — Deploy

Hanya berjalan di branch `main`. Mengkompilasi binary final menggunakan `go build -o app ./...`. Pada environment production, stage ini dapat diperluas untuk melakukan deployment ke server menggunakan Docker, rsync, atau tools lainnya.

### Post Actions

Setelah semua stage selesai (berhasil maupun gagal), Jenkins mengirimkan notifikasi ke Discord berupa embed berwarna hijau (berhasil) atau merah (gagal), lalu membersihkan workspace dengan `cleanWs()`.

```
git push
   ↓
Checkout → Build → Test → SonarQube Analysis → Quality Gate → Deploy
                                                      ↓
                                              PASSED → lanjut Deploy
                                              FAILED → pipeline berhenti
                                                      ↓
                                            Notifikasi Discord (selalu)
```

---

## Penjelasan Integrasi Jenkins & SonarQube

Jenkins dan SonarQube diintegrasikan secara dua arah menggunakan plugin **SonarQube Scanner for Jenkins**.

### Alur Integrasi

```
Jenkins                          SonarQube
   │                                 │
   │── sonar-scanner kirim data ────►│
   │                                 │ (analisis kode)
   │◄── webhook callback ────────────│
   │   (Quality Gate result)         │
   │                                 │
   ▼                                 │
Pipeline lanjut/berhenti             │
```

### Komponen Integrasi

**1. SonarQube Scanner**
sonar-scanner diinstall langsung di dalam Docker image Jenkins (via Dockerfile). Tool ini bertugas mengumpulkan informasi kode (source files, test coverage, dll) dan mengirimkannya ke SonarQube server untuk dianalisis.

**2. SonarQube Server Configuration**
Jenkins menyimpan konfigurasi koneksi ke SonarQube (URL server dan token autentikasi) di **Manage Jenkins → System → SonarQube servers**. Konfigurasi ini diinjeksikan sebagai environment variable ke dalam pipeline menggunakan blok `withSonarQubeEnv('sonarqube')`.

**3. Token Autentikasi**
SonarQube menggunakan token (bukan username/password) untuk autentikasi. Token ini dibuat di SonarQube, lalu disimpan sebagai **Secret text credential** di Jenkins dengan ID `sonarqube-token`. Dengan cara ini token tidak pernah terekspos di Jenkinsfile.

**4. Webhook SonarQube → Jenkins**
Setelah analisis selesai, SonarQube mengirimkan hasil Quality Gate ke Jenkins melalui webhook POST ke endpoint `http://20.205.129.74:8080/sonarqube-webhook/`. Jenkins yang sedang menunggu di stage `waitForQualityGate` akan menerima callback ini dan memutuskan apakah pipeline dilanjutkan atau dihentikan.

Tanpa webhook ini, Jenkins tidak akan pernah menerima hasil Quality Gate dan akan terus menunggu hingga timeout.

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

> Container `jenkins-docker` menggunakan flag `--rm` sehingga akan hilang saat VM di-restart. Jalankan perintah ini terlebih dahulu setiap kali VM dinyalakan ulang, sebelum menjalankan Jenkins.

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

Buka [http://20.205.129.74:9000](http://20.205.129.74:9000)

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
| Server URL | [http://20.205.129.74:9000](http://20.205.129.74:9000) |
| Server authentication token | `sonarqube-token` |

> Nama harus sama persis dengan yang digunakan di Jenkinsfile (`withSonarQubeEnv('sonarqube')`).

### Buat Webhook SonarQube → Jenkins

**SonarQube** → **Administration** → **Webhooks** → **Create**:

| Field | Value |
|-------|-------|
| Name | `Jenkins` |
| URL | [http://20.205.129.74:8080/sonarqube-webhook/](http://20.205.129.74:8080/sonarqube-webhook/) |

---

## 7. Integrasi Jenkins & GitHub

### Generate GitHub Personal Access Token

**GitHub** → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token**:
- Scope: ✅ `repo`, ✅ `admin:repo_hook`
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
| Payload URL | [http://20.205.129.74:8080/github-webhook/](http://20.205.129.74:8080/github-webhook/) |
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
- ✅ GitHub hook trigger for GITScm polling

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

<img width="1309" height="371" alt="screenshot-2026-05-02_11 39 14" src="https://github.com/user-attachments/assets/8728f373-e40f-4c22-abac-98c3fcd41926" />

---

### 2. Jenkins — Console Output Build Berhasil

File teks Console Output dari build terakhir yang diakhiri dengan `Finished: SUCCESS`.

> Cara simpan: buka `http://20.205.129.74:8080/job/demo-jenkins-pipeline/<nomor-build>/consoleText` di browser → Ctrl+S → simpan sebagai `.txt` → taruh di folder `assets/`

[File Output Console](https://github.com/Ckyyy002/Oprec-NCC-2026/blob/module-2/%2317.txt)

---

### 3. Jenkins — Daftar Credentials

Screenshot halaman Credentials yang menampilkan ketiga credential terdaftar: `sonarqube-token`, `github-credentials`, dan `discord-webhook-url`.

> Lokasi: **Manage Jenkins → Credentials → System → Global credentials**

<img width="1610" height="364" alt="screenshot-2026-05-02_11 42 59" src="https://github.com/user-attachments/assets/6b75d6fe-8e28-4482-90f7-9f690a5dc3d4" />

---

### 4. Jenkins — Konfigurasi SonarQube Server

Screenshot halaman System Configuration bagian SonarQube servers yang menampilkan nama server `sonarqube` dan URL [http://20.205.129.74:9000](http://20.205.129.74:9000).

> Lokasi: **Manage Jenkins → System → SonarQube servers**

<img width="1579" height="704" alt="screenshot-2026-05-02_11 43 31" src="https://github.com/user-attachments/assets/a8d26571-5c7d-4864-a1ac-17938f05b739" />

---

### 5. GitHub — Webhook Aktif

Screenshot halaman Webhooks repository GitHub yang menampilkan webhook dengan tanda centang hijau ✅ di kolom Recent Deliveries.

> Lokasi: Repository GitHub → **Settings → Webhooks**

<img width="868" height="225" alt="screenshot-2026-05-02_11 44 38" src="https://github.com/user-attachments/assets/c1594dc1-07b5-4630-8513-5127b105359f" />

---

### 6. SonarQube — Hasil Analisis Kode

Screenshot halaman project di SonarQube yang menampilkan hasil analisis: Bugs, Vulnerabilities, Security Hotspots, Code Smells, Coverage, dan Duplications.

> Lokasi: [http://20.205.129.74:9000/projects](http://20.205.129.74:9000/projects)

<img width="997" height="173" alt="screenshot-2026-05-02_11 45 18" src="https://github.com/user-attachments/assets/d1f4d6b1-eca8-4577-9f5f-b3aa81416413" />

---

### 7. Discord — Notifikasi Build Berhasil

Screenshot channel Discord yang menampilkan embed notifikasi berwarna hijau bertuliskan **✅ Build Berhasil**.

<img width="496" height="163" alt="screenshot-2026-05-02_11 49 11" src="https://github.com/user-attachments/assets/539fe39d-a8e2-4a2f-9e64-53f3279f3bbd" />

---

## Kendala & Solusi

### 1. Jenkins tidak bisa start setelah VM di-restart

**Gejala:** `exec: java: not found` di logs Jenkins.

**Penyebab:** Flag `--env PATH=...` saat `docker run` menimpa PATH default container sehingga Java tidak ditemukan.

**Solusi:** Hapus flag `--env PATH=...` dari perintah `docker run`. PATH untuk Go dan sonar-scanner sudah di-set di dalam Dockerfile via `ENV`, tidak perlu di-override dari luar. Selain itu, container `jenkins-docker` (DinD) menggunakan flag `--rm` sehingga hilang setiap kali VM restart. Jalankan selalu dalam urutan berikut setiap VM dinyalakan:

```bash
# 1. Jalankan DinD terlebih dahulu
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

# 2. Jenkins akan auto-restart karena --restart=on-failure
# Atau jalankan manual jika belum running:
docker start jenkins-blueocean
```

---

### 2. `npm: not found` saat stage Build

**Penyebab:** Repository demo-jenkins adalah project Go, bukan Node.js. Jenkinsfile awal menggunakan `npm install` yang tidak sesuai dengan tech stack.

**Solusi:** Sesuaikan stage Build dan Test di Jenkinsfile dengan perintah Go:

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
