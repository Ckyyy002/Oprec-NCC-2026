# 🐳 Docker — Panduan Lengkap

## Apa itu Docker?

Docker adalah platform open-source untuk mengembangkan, mengirim, dan menjalankan aplikasi di dalam **container**. Container memungkinkan kamu mempaketkan aplikasi beserta semua dependensinya sehingga berjalan konsisten di environment mana pun — dari laptop developer hingga server produksi.

---

## Konsep Dasar

| Konsep | Deskripsi |
|---|---|
| **Image** | Blueprint read-only untuk membuat container (seperti class dalam OOP) |
| **Container** | Instance yang berjalan dari sebuah image (seperti object dari class) |
| **Dockerfile** | File instruksi untuk membangun image |
| **Registry** | Tempat penyimpanan image (e.g. Docker Hub, GHCR) |
| **Volume** | Persistent storage yang bisa di-mount ke container |
| **Network** | Jaringan virtual yang menghubungkan antar container |

---

## Arsitektur Docker

```
┌─────────────────────────────────┐
│         Docker Client           │
│   (docker build / run / push)   │
└────────────────┬────────────────┘
                 │ REST API
┌────────────────▼────────────────┐
│         Docker Daemon           │
│  ┌──────────┐  ┌─────────────┐  │
│  │  Images  │  │  Containers │  │
│  └──────────┘  └─────────────┘  │
│  ┌──────────┐  ┌─────────────┐  │
│  │ Volumes  │  │  Networks   │  │
│  └──────────┘  └─────────────┘  │
└─────────────────────────────────┘
```

---

## Dockerfile

### Struktur Umum

```dockerfile
# Base image
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy dependency files first (caching layer)
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Expose port
EXPOSE 3000

# Run command
CMD ["node", "server.js"]
```

### Multi-Stage Build

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:20-alpine AS runner
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

> **Tips:** Multi-stage build drastis mengurangi ukuran image final karena hanya menyertakan artifact yang dibutuhkan saat runtime.

---

## Perintah Docker Penting

### Image Management

```bash
# Build image dari Dockerfile
docker build -t myapp:1.0 .

# List semua image
docker images

# Pull image dari registry
docker pull nginx:alpine

# Push image ke registry
docker push username/myapp:1.0

# Hapus image
docker rmi myapp:1.0

# Hapus semua dangling images
docker image prune
```

### Container Management

```bash
# Jalankan container
docker run -d -p 8080:3000 --name myapp myapp:1.0

# List container yang berjalan
docker ps

# List semua container (termasuk yang stopped)
docker ps -a

# Stop container
docker stop myapp

# Masuk ke dalam container
docker exec -it myapp sh

# Lihat logs
docker logs -f myapp

# Hapus container
docker rm myapp
```

### Volume & Network

```bash
# Buat volume
docker volume create mydata

# Mount volume saat run
docker run -v mydata:/app/data myapp:1.0

# Buat network
docker network create mynetwork

# Jalankan container dalam network tertentu
docker run --network mynetwork myapp:1.0
```

---

## Docker Compose

Docker Compose digunakan untuk mendefinisikan dan menjalankan **multi-container** application.

### Contoh `docker-compose.yml`

```yaml
version: '3.9'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: myapp
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://user:pass@db:5432/mydb
    depends_on:
      db:
        condition: service_healthy
    networks:
      - app-network
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    container_name: mydb
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  nginx:
    image: nginx:alpine
    container_name: mynginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - app
    networks:
      - app-network

volumes:
  pgdata:

networks:
  app-network:
    driver: bridge
```

### Perintah Docker Compose

```bash
# Jalankan semua service
docker compose up -d

# Build ulang dan jalankan
docker compose up -d --build

# Stop semua service
docker compose down

# Stop dan hapus volume
docker compose down -v

# Lihat logs semua service
docker compose logs -f

# Scale service tertentu
docker compose up -d --scale app=3
```

---

## Best Practices

### 1. Optimasi Image Size
- Gunakan base image minimal (Alpine, Distroless)
- Manfaatkan **layer caching** — taruh instruksi yang jarang berubah di atas
- Gunakan `.dockerignore` untuk exclude file tidak perlu

```
# .dockerignore
node_modules/
.git/
*.log
dist/
.env
```

### 2. Security
- Jangan jalankan container sebagai `root`
- Scan image dengan `docker scout` atau Trivy
- Gunakan image dari official/verified source
- Set `--read-only` filesystem bila memungkinkan

```dockerfile
# Tambahkan non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```

### 3. Resource Limits

```bash
docker run \
  --memory="512m" \
  --cpus="1.0" \
  myapp:1.0
```

---

## Troubleshooting

| Masalah | Solusi |
|---|---|
| Container langsung exit | Cek logs: `docker logs <container>` |
| Port sudah digunakan | Ganti port mapping atau stop service lain |
| Image build lambat | Manfaatkan BuildKit: `DOCKER_BUILDKIT=1 docker build` |
| Out of disk space | `docker system prune -a` untuk bersihkan resource tak terpakai |

---

## Referensi

- [Docker Official Docs](https://docs.docker.com)
- [Docker Hub](https://hub.docker.com)
- [Play with Docker](https://labs.play-with-docker.com)
