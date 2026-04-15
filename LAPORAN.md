# Laporan Penugasan Oprec NCC 2026 — Pertemuan 1 (Docker)

**Nama:** Lucky Himawan Prasetya

**NRP:** 5025241147

**Platform VPS:** Microsoft Azure

**IP Publik:** [20.205.136.147](http://20.205.136.147/health)

**Bahasa / Framework:** Python 3.12 / FastAPI + Uvicorn

---

## 1. Deskripsi Singkat Service

Service yang dibuat adalah **REST API minimalis berbasis FastAPI (Python)** yang berjalan di dalam Docker container. Service ini dirancang untuk memenuhi kebutuhan health check deployment, dengan menyediakan endpoint `/health` yang mengembalikan status `200 OK` beserta informasi timestamp secara real-time dalam format waktu **WIB (UTC+7)** yang mudah dibaca.

Service dijalankan menggunakan **Uvicorn** sebagai ASGI server, dengan container berbasis **Python 3.12 Alpine** untuk menjaga ukuran image tetap ringan dan efisien.

### Struktur Project

```
health-service/
├── app.py              # Source code FastAPI
├── requirements.txt    # Dependency Python
├── Dockerfile          # Multi-stage build (Alpine)
├── docker-compose.yml  # Orkestrasi container
├── .env                # Environment variable
├── .dockerignore       # Optimasi build context
└── LAPORAN.md          # Laporan 
```

---

## 2. Penjelasan Endpoint `/health`

Service menyediakan dua endpoint:

| Method | Endpoint  | Status Code | Deskripsi                                   |
|--------|-----------|-------------|---------------------------------------------|
| GET    | `/`       | 200 OK      | Info service & status running               |
| GET    | `/health` | **200 OK**  | Health check — mengembalikan status service |

### Source Code (`app.py`)

```python
from fastapi import FastAPI
from datetime import datetime, timezone, timedelta

app = FastAPI(title="Health Service", version="1.0.0")

WIB = timezone(timedelta(hours=7))

def now_wib():
    return datetime.now(WIB).strftime("%d %B %Y, %H:%M:%S WIB")


@app.get("/")
def root():
    return {
        "author": "Oprec Admin NCC 2026 - Lucky Himawan Prasetya",
        "service": "NCC 2026 Health Service",
        "status": "running",
        "timestamp": now_wib(),
        "message": "bismillah diterima",
    }


@app.get("/health")
def health_check():
    return {
        "author": "Oprec Admin NCC 2026 - Lucky Himawan Prasetya",
        "status": "ok",
        "uptime": "healthy",
        "timestamp": now_wib(),
        "message": "bismillah diterima",
    }
```

### Contoh Response `/health`

```json
{
  "author": "Oprec Admin NCC 2026 - Lucky Himawan Prasetya",

  "status": "ok",
  "uptime": "healthy",

  "timestamp": "14 April 2026, 23:08:37 WIB",

  "message": "bismillah diterima"
}
```

---

## 3. Bukti Endpoint dapat Diakses

Endpoint `/health` berhasil diakses secara publik dari luar VPS menggunakan `curl`:

```
curl -v --connect-timeout 10 http://20.205.136.147/health
```

Output:
```
*   Trying 20.205.136.147:80...
* Established connection to 20.205.136.147 (20.205.136.147 port 80) from 192.168.3.57 port 34686 
* using HTTP/1.x
> GET /health HTTP/1.1
> Host: 20.205.136.147
> User-Agent: curl/8.19.0
> Accept: */*
> 
* Request completely sent off
< HTTP/1.1 200 OK
< date: Wed, 15 Apr 2026 01:05:13 GMT
< server: uvicorn
< content-length: 164
< content-type: application/json
< 
* Connection #0 to host 20.205.136.147:80 left intact
{"author":"Oprec Admin NCC 2026 - Lucky Himawan Prasetya","status":"ok","uptime":"healthy","timestamp":"15 April 2026, 08:05:14 WIB","message":"bismillah diterima"}
```

✅ **Endpoint dapat diakses publik di: [http://20.205.136.147/health](http://20.205.136.147/health)**

---

## 4. Penjelasan Proses Build dan Run Docker

### 4.1 Dockerfile — Multi-Stage Build

```dockerfile
FROM python:3.12-alpine AS builder

WORKDIR /app

RUN apk add --no-cache gcc musl-dev

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-alpine AS runtime

WORKDIR /app

COPY --from=builder /install /usr/local
COPY app.py .

ENV APP_ENV=production \
    APP_PORT=8000 \
    APP_HOST=0.0.0.0

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8000/health || exit 1

RUN adduser -D appuser
USER appuser

CMD ["sh", "-c", "uvicorn app:app --host $APP_HOST --port $APP_PORT"]
```

**Penjelasan:**
- **Stage 1 (builder):** Install `gcc` dan semua dependency Python ke direktori `/install`. Build tools tidak dibawa ke image final.
- **Stage 2 (runtime):** Hanya menyalin hasil install dari stage builder (`COPY --from=builder`). Image final bersih, kecil, dan tidak mengandung compiler.
- **Non-root user:** App dijalankan sebagai `appuser`, bukan root, untuk keamanan.
- **HEALTHCHECK:** Docker otomatis memeriksa kesehatan container setiap 30 detik via endpoint `/health`.

### 4.2 Docker Compose (`docker-compose.yml`)

```yaml
services:
  health-service:
    build: .
    container_name: health-service
    ports:
      - "${APP_PORT:-80}:8000"
    environment:
      - APP_ENV=${APP_ENV:-production}
      - APP_HOST=0.0.0.0
      - APP_PORT=8000
    env_file:
      - .env
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8000/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

### 4.3 Perintah Build dan Run

```bash
# Build image dan jalankan container di background
docker compose up -d --build

# Cek status container
docker compose ps

# Lihat log container
docker compose logs health-service

# Test endpoint dari dalam VPS
curl http://localhost/health
```

### 4.4 Fitur Opsional yang Diimplementasikan

| Fitur | Status | Detail |
|-------|--------|--------|
| Multi-stage build | ✅ | Stage `builder` + stage `runtime` |
| Optimasi ukuran image | ✅ | Base image `python:3.12-alpine` |
| `HEALTHCHECK` di Dockerfile | ✅ | Interval 30s, timeout 5s, retries 3 |
| Docker Compose | ✅ | `docker-compose.yml` lengkap |
| Environment variable | ✅ | `ENV` di Dockerfile + file `.env` |
| `.dockerignore` | ✅ | Exclude cache, `.git`, `.env`, IDE files |
| Restart policy | ✅ | `unless-stopped` |
| Port configuration | ✅ | Port jelas `80:8000`, customizable via `.env` |
| Struktur Dockerfile clean | ✅ | Komentar per-stage, non-root user, layer caching optimal |

---

## 5. Penjelasan Proses Deployment ke VPS

Deployment dilakukan ke **Virtual Machine Microsoft Azure**.

### Langkah-langkah

**1. SSH ke VPS**
```bash
ssh lucky@20.205.136.147
```

**2. Install Docker di VPS**
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Logout dan login kembali agar grup Docker aktif
```

**3. Transfer file project ke VPS (dari local)**
```bash
scp -r ./health-service lucky@20.205.136.147:~/health-service
```

**4. Jalankan service**
```bash
cd ~/health-service
docker compose up -d
```

**5. Buka port di Azure Portal**

Karena VPS menggunakan Microsoft Azure, port perlu dibuka di **Network Security Group (NSG)**:
- Buka Azure Portal → Virtual Machines → VM → **Networking**
- Klik **Add Inbound Port Rule**
- Isi: Port `80`, Protocol `TCP`, Action `Allow`, Priority `100`
- Klik **Add** dan tunggu rule aktif

**6. Verifikasi akses publik**
```bash
curl http://20.205.136.147/health
```

---
