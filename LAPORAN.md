# 📊 Laporan Penugasan: Monitoring System dengan Prometheus & Grafana

> **Oprec NCC Laboratory 2026 — Pertemuan 3**
> VM Azure — Public IP: `57.158.27.100`

---

## 📋 Daftar Isi

1. [Deskripsi Arsitektur Sistem Monitoring](#1-deskripsi-arsitektur-sistem-monitoring)
2. [Infrastruktur yang Digunakan](#2-infrastruktur-yang-digunakan)
3. [Instalasi dan Konfigurasi Prometheus](#3-instalasi-dan-konfigurasi-prometheus)
4. [Instalasi Node Exporter](#4-instalasi-node-exporter)
5. [Instalasi dan Konfigurasi Grafana](#5-instalasi-dan-konfigurasi-grafana)
6. [Integrasi Prometheus dengan Grafana](#6-integrasi-prometheus-dengan-grafana)
7. [Custom Dashboard Grafana](#7-custom-dashboard-grafana)
8. [Alur Monitoring (Metrics → Prometheus → Grafana → Alert)](#8-alur-monitoring)
9. [Sistem Alerting (Poin Opsional)](#9-sistem-alerting-poin-opsional)
10. [Integrasi Alert ke Webhook Discord (Poin Opsional)](#10-integrasi-alert-ke-webhook-discord-poin-opsional)
11. [Query PromQL Kompleks (Poin Opsional)](#11-query-promql-kompleks-poin-opsional)
12. [Simulasi Anomali](#12-simulasi-anomali)
13. [Kendala yang Dihadapi](#13-kendala-yang-dihadapi)
14. [Kesimpulan](#14-kesimpulan)

---

## 1. Deskripsi Arsitektur Sistem Monitoring

Sistem monitoring ini dibangun menggunakan tiga komponen utama yang saling terintegrasi:

| Komponen | Fungsi |
|---|---|
| **Node Exporter** | Mengekspos metrics sistem operasi (CPU, RAM, Disk, Network) melalui HTTP endpoint |
| **Prometheus** | Scraping (pull) metrics dari Node Exporter, menyimpannya sebagai time-series data |
| **Grafana** | Visualisasi data dari Prometheus dalam bentuk dashboard interaktif + alerting |

### Arsitektur Jaringan

Karena hanya menggunakan **1 VM Azure** (IP Publik: `57.158.27.100`), semua komponen berjalan di satu mesin dengan komunikasi via `localhost`:

```
Internet
    |
  HTTP
    |
[VM Azure — 57.158.27.100]
    |
    ├── Grafana       → port 3000  (publik)
    ├── Prometheus    → port 9090  (lokal / dibatasi)
    └── Node Exporter → port 9100  (lokal / dibatasi)

Alur data:
Node Exporter (:9100) ──scrape──► Prometheus (:9090) ──query──► Grafana (:3000)
                                                                      │
                                                              Alert Manager
                                                                      │
                                                               Discord Webhook
```

### Konfigurasi Port Azure NSG (Network Security Group)

| Port | Protokol | Sumber | Keterangan |
|------|----------|--------|------------|
| 22 | TCP | My IP | SSH akses |
| 3000 | TCP | Any | Grafana Dashboard |
| 9090 | TCP | 127.0.0.1 | Prometheus (lokal saja) |
| 9100 | TCP | 127.0.0.1 | Node Exporter (lokal saja) |

> **Catatan Keamanan:** Port 9090 dan 9100 tidak diekspos ke publik. Hanya Grafana (3000) yang dapat diakses dari internet.

---

## 2. Infrastruktur yang Digunakan

| Detail | Nilai |
|--------|-------|
| Provider | Microsoft Azure |
| OS | Ubuntu 22.04 LTS |
| Public IP | `57.158.27.100` |
| CPU | 2 vCPU |
| RAM | 7.7 GB |
| Disk | 29 GB |

### Langkah Awal — Update & Upgrade VM

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget gnupg2 software-properties-common
```

---

## 3. Instalasi dan Konfigurasi Prometheus

### 3.1 Download & Install Prometheus

```bash
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v2.52.0/prometheus-2.52.0.linux-amd64.tar.gz

# Extract
tar xvf prometheus-*.tar.gz
cd prometheus-*.linux-amd64

# Pindahkan binary ke system path
sudo mv prometheus /usr/local/bin/
sudo mv promtool /usr/local/bin/

# Buat direktori konfigurasi dan data
sudo mkdir -p /etc/prometheus
sudo mkdir -p /var/lib/prometheus

# Copy file konfigurasi default
sudo cp prometheus.yml /etc/prometheus/

# Buat user khusus (keamanan)
sudo useradd --no-create-home --shell /bin/false prometheus

# Set kepemilikan direktori
sudo chown prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chown prometheus:prometheus /usr/local/bin/promtool
```

### 3.2 Konfigurasi Systemd Service

```bash
sudo nano /etc/systemd/system/prometheus.service
```

Isi dengan:

```ini
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --storage.tsdb.retention.time=7d \
  --web.listen-address=127.0.0.1:9090

Restart=always

[Install]
WantedBy=multi-user.target
```

> **Catatan:** `--web.listen-address=127.0.0.1:9090` memastikan Prometheus hanya bisa diakses dari lokal (keamanan).

### 3.3 Jalankan Prometheus

```bash
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus
sudo systemctl status prometheus
```

### Screenshot: Status Prometheus

> 📸 *[Screenshot: `sudo systemctl status prometheus` menunjukkan status `active (running)`]*

### 3.4 Konfigurasi `prometheus.yml`

```bash
TERM=xterm-256color sudo nano /etc/prometheus/prometheus.yml
```

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Scrape Prometheus sendiri
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # Scrape Node Exporter
  - job_name: "node_exporter"
    static_configs:
      - targets: ["localhost:9100"]
```

```bash
# Restart setelah edit config
sudo systemctl restart prometheus
sudo systemctl status prometheus
```

### Screenshot: File prometheus.yml

> 📸 *[Screenshot: isi file `/etc/prometheus/prometheus.yml`]*

---

## 4. Instalasi Node Exporter

### 4.1 Download & Install

```bash
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.1/node_exporter-1.8.1.linux-amd64.tar.gz

tar xvf node_exporter-*.tar.gz
cd node_exporter-*.linux-amd64

sudo mv node_exporter /usr/local/bin/

# Buat user khusus
sudo useradd --no-create-home --shell /bin/false node_exporter
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
```

### 4.2 Konfigurasi Systemd Service

```bash
sudo nano /etc/systemd/system/node_exporter.service
```

```ini
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=127.0.0.1:9100

Restart=always

[Install]
WantedBy=multi-user.target
```

### 4.3 Jalankan Node Exporter

```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
sudo systemctl status node_exporter
```

### Screenshot: Node Exporter Running

> 📸 *[Screenshot: `sudo systemctl status node_exporter` menunjukkan status `active (running)`]*

### Verifikasi Metrics

```bash
curl -s http://localhost:9100/metrics | head -30
```

> 📸 *[Screenshot: output curl menampilkan metrics seperti `node_cpu_seconds_total`, `node_memory_MemTotal_bytes`, dll]*

---

## 5. Instalasi dan Konfigurasi Grafana

### 5.1 Install Grafana

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https wget gnupg

# Tambahkan GPG key Grafana
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
sudo chmod 644 /etc/apt/keyrings/grafana.asc

# Tambahkan repository Grafana
echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" | \
  sudo tee /etc/apt/sources.list.d/grafana.list

# Install
sudo apt-get update
sudo apt-get install -y grafana
```

### 5.2 Jalankan Grafana

```bash
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
sudo systemctl status grafana-server
```

### 5.3 Akses Grafana

Buka browser dan akses:

```
http://57.158.27.100:3000
```

Login awal:
- **Username:** `admin`
- **Password:** `admin`

Grafana akan meminta untuk mengganti password. Ganti dengan password yang aman.

### Screenshot: Halaman Login Grafana

> 📸 *[Screenshot: halaman login Grafana di `http://57.158.27.100:3000`]*

### Screenshot: Dashboard Utama Grafana

> 📸 *[Screenshot: halaman home Grafana setelah login berhasil]*

---

## 6. Integrasi Prometheus dengan Grafana

### 6.1 Tambahkan Data Source Prometheus

1. Di Grafana, buka **Connections → Data sources**
2. Klik **"Add data source"**
3. Pilih **Prometheus**
4. Isi konfigurasi:

| Field | Value |
|-------|-------|
| Name | `Prometheus-Azure` |
| URL | `http://localhost:9090` |
| Access | Server (default) |
| Scrape interval | `15s` |

5. Klik **"Save & Test"** — pastikan muncul tanda ✅ hijau

### Screenshot: Konfigurasi Data Source

> 📸 *[Screenshot: form konfigurasi data source Prometheus di Grafana]*

### Screenshot: Data Source Test Berhasil

> 📸 *[Screenshot: pesan "Data source connected and labels found." di Grafana]*

### 6.2 Verifikasi Targets di Prometheus

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"job"'
```

### Screenshot: Prometheus Targets

> 📸 *[Screenshot: output menampilkan semua target dengan status `"health": "up"`]*

---

## 7. Custom Dashboard Grafana

Custom dashboard dibuat **tanpa menggunakan template bawaan** (tanpa import dashboard ID 1860). Semua panel dibuat manual menggunakan query PromQL.

### Cara Membuat Dashboard Baru

1. Klik **"+" → New Dashboard → Add visualization**
2. Pilih data source **Prometheus-Azure**
3. Masukkan query PromQL sesuai panel yang diinginkan

---

### Panel 1 — CPU Usage: Tren (Time Series)

| Field | Value |
|-------|-------|
| **Judul** | `CPU Usage (%) — Tren` |
| **Tipe** | **Time series** |
| **Unit** | Percent (0-100) |
| **Fill opacity** | 20 (agar area di bawah garis terisi tipis) |
| **Line width** | 2 |

**Query:**
```promql
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Konfigurasi Threshold (Thresholds):**
- Hijau: 0%
- Kuning: 70%
- Merah: 90%

> Panel ini menampilkan **riwayat CPU** dalam rentang waktu tertentu sehingga mudah melihat kapan terjadi lonjakan.

---

### Panel 2 — CPU Usage: Nilai Saat Ini (Gauge)

| Field | Value |
|-------|-------|
| **Judul** | `CPU Usage (%) — Sekarang` |
| **Tipe** | **Gauge** |
| **Unit** | Percent (0-100) |
| **Min** | 0 |
| **Max** | 100 |
| **Show threshold labels** | On |
| **Show threshold markers** | On |

**Query:**
```promql
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Konfigurasi Threshold:**
- Hijau: 0–70%
- Kuning: 70–90%
- Merah: 90–100%

> Gauge menampilkan **nilai CPU saat ini** dalam bentuk jarum/arc berwarna sehingga status server langsung terlihat sekilas.

---

### Panel 3 — Memory Usage (Gauge)

| Field | Value |
|-------|-------|
| **Judul** | `Memory Usage (%)` |
| **Tipe** | **Gauge** |
| **Unit** | Percent (0-100) |
| **Min** | 0 |
| **Max** | 100 |
| **Show threshold labels** | On |
| **Show threshold markers** | On |

**Query:**
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

**Konfigurasi Threshold:**
- Hijau: 0–80%
- Kuning: 80–95%
- Merah: 95–100%

> Gauge cocok untuk memory karena pengguna cukup tahu angka persentase saat ini, bukan riwayatnya.

---

### Panel 4 — Disk Usage (Bar Gauge)

| Field | Value |
|-------|-------|
| **Judul** | `Disk Usage (/)` |
| **Tipe** | **Bar gauge** |
| **Unit** | Percent (0-100) |
| **Orientation** | Horizontal |
| **Display mode** | Retro LCD (atau Basic) |
| **Min** | 0 |
| **Max** | 100 |

**Query:**
```promql
(1 - (node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"})) * 100
```

**Konfigurasi Threshold:**
- Hijau: 0–75%
- Kuning: 75–90%
- Merah: 90–100%

> Bar gauge lebih intuitif untuk disk karena tampilannya seperti progress bar — mudah dibaca seberapa penuh storage tanpa perlu membaca angka.

---

### Panel 5 — Network Traffic (Time Series)

| Field | Value |
|-------|-------|
| **Judul** | `Network Traffic` |
| **Tipe** | **Time series** |
| **Unit** | bytes/sec (SI) |
| **Fill opacity** | 15 |
| **Line width** | 2 |

**Query A — Receive:**
```promql
rate(node_network_receive_bytes_total{device!="lo"}[5m])
```
Legend: `Receive`

**Query B — Transmit:**
```promql
rate(node_network_transmit_bytes_total{device!="lo"}[5m])
```
Legend: `Transmit`

> Time series tepat untuk network karena traffic berubah terus — dengan dua line berbeda warna, receive vs transmit langsung bisa dibandingkan.

---

### Panel 6 — System Uptime (Stat)

| Field | Value |
|-------|-------|
| **Judul** | `System Uptime` |
| **Tipe** | **Stat** |
| **Unit** | Hours |
| **Color mode** | Background |
| **Graph mode** | None |
| **Text size** | Auto |

**Query:**
```promql
(time() - node_boot_time_seconds) / 3600
```

> Stat menampilkan satu angka besar yang langsung terbaca. Background berwarna hijau memberikan kesan sistem berjalan normal.

---

### Panel 7 — Load Average (Time Series)

| Field | Value |
|-------|-------|
| **Judul** | `System Load Average` |
| **Tipe** | **Time series** |
| **Unit** | None (Short) |
| **Fill opacity** | 10 |
| **Line width** | 2 |
| **Soft max** | 2 (sesuai jumlah CPU core) |

**Query A:**
```promql
node_load1
```
Legend: `Load 1m`

**Query B:**
```promql
node_load5
```
Legend: `Load 5m`

**Query C:**
```promql
node_load15
```
Legend: `Load 15m`

> Setiap query dimasukkan **terpisah** dengan klik **"+ Add query"**. Tambahkan **reference line** (Constant) di angka `2` (jumlah vCPU) sebagai batas normal agar mudah terlihat kapan sistem mulai kewalahan.

---

### Screenshot: Custom Dashboard Overview

> 📸 *[Screenshot: tampilan lengkap custom dashboard dengan semua panel]*

### Screenshot: Panel CPU (Time Series + Gauge berdampingan)

> 📸 *[Screenshot: panel CPU tren dan gauge nilai saat ini]*

### Screenshot: Panel Disk Bar Gauge

> 📸 *[Screenshot: panel disk usage dalam bentuk bar gauge horizontal]*

---

## 8. Alur Monitoring

Berikut adalah alur lengkap sistem monitoring dari pengumpulan data hingga visualisasi dan alert:

```
┌─────────────────────────────────────────────────────────────┐
│                    VM Azure (57.158.27.100)                  │
│                                                              │
│  ┌──────────────┐    pull/scrape     ┌──────────────────┐   │
│  │ Node Exporter│ ◄─────────────── ► │    Prometheus    │   │
│  │  port: 9100  │  setiap 15 detik   │   port: 9090     │   │
│  │              │                    │                  │   │
│  │ Mengekspos:  │                    │ Menyimpan:       │   │
│  │ - CPU metrics│                    │ - Time-series DB │   │
│  │ - RAM metrics│                    │ - Evaluasi rules │   │
│  │ - Disk I/O   │                    │                  │   │
│  │ - Network    │                    │                  │   │
│  └──────────────┘                    └────────┬─────────┘   │
│                                               │             │
│                                            PromQL query     │
│                                               │             │
│                                      ┌────────▼─────────┐   │
│                                      │     Grafana      │   │
│                                      │   port: 3000     │   │
│                                      │                  │   │
│                                      │ - Dashboard      │   │
│                                      │ - Alert rules    │   │
│                                      │ - Visualisasi    │   │
│                                      └────────┬─────────┘   │
│                                               │             │
└───────────────────────────────────────────────┼─────────────┘
                                                │
                                       ┌────────▼────────┐
                                       │ Discord Webhook │
                                       └─────────────────┘
```

**Penjelasan alur:**

1. **Node Exporter** berjalan di port 9100 (localhost only), terus menerus mengekspos metrics sistem dalam format teks yang bisa dibaca Prometheus.
2. **Prometheus** setiap 15 detik melakukan **scraping** ke endpoint `http://localhost:9100/metrics`, menyimpan data dalam time-series database internal.
3. **Grafana** terhubung ke Prometheus sebagai **data source**, mengirimkan **query PromQL** untuk mengambil data yang dibutuhkan setiap panel dashboard.
4. Jika ada **alert rule** yang terpenuhi (contoh: CPU > 85%), Grafana akan mengirimkan notifikasi ke Discord melalui webhook.

---

## 9. Sistem Alerting (Poin Opsional)

### 9.1 Konfigurasi Alert Rule di Grafana

Di Grafana, buka **Alerting → Alert rules → New alert rule**

Untuk setiap rule, isi:
- **Folder:** `General`
- **Evaluation group:** `default` dengan interval `1m`

---

#### Alert Rule 1: CPU Usage Tinggi

| Field | Value |
|-------|-------|
| **Nama** | `High CPU Usage` |
| **Query** | `100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| **Kondisi** | `IS ABOVE 85` |
| **For** | `2m` |
| **Summary** | `CPU usage tinggi di instance` |

---

#### Alert Rule 2: Memory Usage Tinggi

| Field | Value |
|-------|-------|
| **Nama** | `High Memory Usage` |
| **Query** | `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100` |
| **Kondisi** | `IS ABOVE 90` |
| **For** | `3m` |
| **Summary** | `Memory usage tinggi di instance` |

---

#### Alert Rule 3: Disk Usage Tinggi

| Field | Value |
|-------|-------|
| **Nama** | `High Disk Usage` |
| **Query** | `(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100` |
| **Kondisi** | `IS ABOVE 80` |
| **For** | `5m` |
| **Summary** | `Disk usage tinggi di instance` |

---

#### Alert Rule 4: Instance Down

| Field | Value |
|-------|-------|
| **Nama** | `Instance Down` |
| **Query** | `up{job="node_exporter"}` |
| **Kondisi** | `IS BELOW 1` |
| **For** | `1m` |
| **Summary** | `Node Exporter tidak dapat dijangkau` |

---

### Screenshot: Alert Rules List

> 📸 *[Screenshot: halaman "Alert rules" di Grafana menampilkan semua rule yang dibuat]*

### Screenshot: Alert Rule Detail CPU

> 📸 *[Screenshot: detail konfigurasi alert rule CPU Usage]*

---

## 10. Integrasi Alert ke Webhook Discord (Poin Opsional)

### 10.1 Membuat Discord Webhook

1. Buka Discord Server
2. Pilih channel yang ingin menerima notifikasi
3. Klik ⚙️ **Edit Channel → Integrations → Webhooks → New Webhook**
4. Beri nama (contoh: `Grafana Alerts`)
5. Klik **Copy Webhook URL**

Contoh format URL:
```
https://discord.com/api/webhooks/XXXXXXXXXXXXXXXXXX/YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```

### 10.2 Konfigurasi Contact Point di Grafana

1. Buka **Alerting → Contact points → Add contact point**
2. Konfigurasi:

| Field | Value |
|-------|-------|
| **Name** | `Discord-Alerts` |
| **Integration** | `Discord` |
| **Webhook URL** | `https://discord.com/api/webhooks/...` |

3. Klik **Test** untuk mengirim pesan percobaan ke Discord
4. Klik **Save contact point**

### 10.3 Konfigurasi Notification Policy

1. Buka **Alerting → Notification policies**
2. Edit **Default policy**:

| Field | Value |
|-------|-------|
| **Contact point** | `Discord-Alerts` |
| **Group by** | `alertname` |
| **Group wait** | `30s` |
| **Group interval** | `5m` |
| **Repeat interval** | `4h` |

### Screenshot: Contact Point Discord

> 📸 *[Screenshot: konfigurasi contact point Discord di Grafana]*

### Screenshot: Test Notifikasi ke Discord

> 📸 *[Screenshot: pesan test yang diterima di channel Discord]*

### Screenshot: Notifikasi Alert di Discord

> 📸 *[Screenshot: pesan alert yang diterima di channel Discord saat CPU tinggi]*

---

## 11. Query PromQL Kompleks (Poin Opsional)

Berikut panel-panel tambahan yang menggunakan query PromQL lebih kompleks:

---

### Panel 8 — CPU Usage per Mode (Stacked Bar)

| Field | Value |
|-------|-------|
| **Judul** | `CPU Usage per Mode` |
| **Tipe** | **Time series** |
| **Unit** | Percent (0-100) |
| **Stacking** | Normal (aktifkan di bagian Graph styles) |
| **Fill opacity** | 80 |

Menampilkan breakdown CPU berdasarkan mode sehingga langsung terlihat proporsi tiap aktivitas dalam satu area yang ditumpuk.

**Query A — User:**
```promql
avg(rate(node_cpu_seconds_total{mode="user"}[5m])) * 100
```
Legend: `User`

**Query B — System:**
```promql
avg(rate(node_cpu_seconds_total{mode="system"}[5m])) * 100
```
Legend: `System`

**Query C — I/O Wait:**
```promql
avg(rate(node_cpu_seconds_total{mode="iowait"}[5m])) * 100
```
Legend: `I/O Wait`

**Query D — Steal:**
```promql
avg(rate(node_cpu_seconds_total{mode="steal"}[5m])) * 100
```
Legend: `Steal`

> Dengan stacking aktif, keempat mode akan tampil sebagai **area yang ditumpuk** sehingga mudah melihat kontribusi masing-masing mode terhadap total CPU usage. **CPU Steal** yang tinggi (> 10%) menandakan VM kekurangan resource dari host.

---

### Panel 9 — Disk I/O Rate (Time Series)

| Field | Value |
|-------|-------|
| **Judul** | `Disk I/O Rate` |
| **Tipe** | **Time series** |
| **Unit** | bytes/sec (SI) |
| **Fill opacity** | 15 |
| **Line width** | 2 |

Menampilkan kecepatan baca dan tulis disk secara real-time.

**Query A — Read:**
```promql
rate(node_disk_read_bytes_total[5m])
```
Legend: `Read`

**Query B — Write:**
```promql
rate(node_disk_written_bytes_total[5m])
```
Legend: `Write`

---

### Panel 10 — Disk IOPS (Stat)

| Field | Value |
|-------|-------|
| **Judul** | `Disk IOPS (saat ini)` |
| **Tipe** | **Stat** |
| **Unit** | ops/sec (iops) |
| **Color mode** | Background |
| **Graph mode** | None |
| **Calculation** | Last (tidak perlu riwayat, cukup nilai sekarang) |

Menampilkan jumlah operasi baca/tulis per detik saat ini.

**Query A — Read IOPS:**
```promql
rate(node_disk_reads_completed_total[5m])
```
Legend: `Read IOPS`

**Query B — Write IOPS:**
```promql
rate(node_disk_writes_completed_total[5m])
```
Legend: `Write IOPS`

> Stat dipilih karena untuk IOPS cukup tahu nilai saat ini — bukan riwayatnya. Dua kotak stat berdampingan (read dan write) lebih ringkas daripada grafik penuh.

---

### Panel 11 — Memory Detail (Stacked Area)

| Field | Value |
|-------|-------|
| **Judul** | `Memory Detail` |
| **Tipe** | **Time series** |
| **Unit** | bytes (SI) |
| **Stacking** | Normal (aktifkan di Graph styles) |
| **Fill opacity** | 70 |

Menampilkan breakdown penggunaan memory secara detail dalam bentuk area yang ditumpuk.

**Query A — Used:**
```promql
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes
```
Legend: `Used`

**Query B — Cache + Buffer:**
```promql
node_memory_Cached_bytes + node_memory_Buffers_bytes
```
Legend: `Cache/Buffer`

**Query C — Free:**
```promql
node_memory_MemFree_bytes
```
Legend: `Free`

> Dengan stacking, tiga area warna (used, cache, free) akan membentuk satu blok penuh setara total RAM — sangat intuitif untuk melihat proporsi pemakaian memory secara keseluruhan.

---

### Panel 12 — Prediksi Disk Penuh (Stat)

| Field | Value |
|-------|-------|
| **Judul** | `Prediksi Sisa Ruang Disk 24 Jam ke Depan` |
| **Tipe** | **Stat** |
| **Unit** | Gigabytes |
| **Color mode** | Background |
| **Thresholds** | Merah jika < 5GB, Kuning jika < 10GB, Hijau jika ≥ 10GB |
| **Calculation** | Last |

```promql
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24*3600) / 1073741824
```

> Jika nilai yang ditampilkan **negatif atau mendekati 0**, background akan berubah merah sebagai peringatan bahwa disk diprediksi penuh dalam 24 jam ke depan.

---

### Panel 13 — Network Traffic: Average vs Peak (Time Series)

| Field | Value |
|-------|-------|
| **Judul** | `Network Receive — Avg vs Peak` |
| **Tipe** | **Time series** |
| **Unit** | bytes/sec (SI) |
| **Fill opacity** | 10 |
| **Line width** | 2 |
| **Line style** | Average: solid, Peak: dashed |

**Query A — Average (10 menit terakhir):**
```promql
avg_over_time(rate(node_network_receive_bytes_total{device!="lo"}[5m])[10m:1m])
```
Legend: `Avg Receive`

**Query B — Peak (1 jam terakhir):**
```promql
max_over_time(rate(node_network_receive_bytes_total{device!="lo"}[5m])[1h:5m])
```
Legend: `Peak Receive`

> Dua line dalam satu panel memudahkan perbandingan antara traffic rata-rata dan traffic puncak — berguna untuk mendeteksi apakah ada lonjakan traffic yang tidak biasa.

---

### Screenshot: Panel CPU Stacked per Mode

> 📸 *[Screenshot: panel CPU per mode dalam tampilan stacked area]*

### Screenshot: Panel Memory Stacked Detail

> 📸 *[Screenshot: panel memory detail dalam tampilan stacked area (used, cache, free)]*

### Screenshot: Panel Disk IOPS Stat

> 📸 *[Screenshot: panel disk IOPS menampilkan dua kotak stat read dan write]*

### Screenshot: Panel Prediksi Disk

> 📸 *[Screenshot: panel prediksi disk dengan background hijau/kuning/merah]*

---

## 12. Simulasi Anomali

### 12.1 Stress Test CPU

```bash
sudo apt install stress-ng -y

# Stress 2 core dengan 95% load selama 120 detik
stress-ng --cpu 2 --cpu-load 95 --timeout 120s
```

### 12.2 Stress Test Memory

```bash
# Alokasikan 6.5GB RAM selama 120 detik
stress-ng --vm 1 --vm-bytes 6500M --vm-keep --timeout 120s
```

### 12.3 Stress Test Disk I/O

```bash
# Tulis file besar (~20GB) untuk meningkatkan disk usage
dd if=/dev/zero of=/tmp/bigfile bs=1M count=20000

# Setelah screenshot, hapus file
rm /tmp/bigfile
```

### Tips: Turunkan Threshold Sementara untuk Demo

Jika resource VM terlalu besar dan stress test tidak cukup memicu alert, ubah sementara threshold di **Grafana → Alerting → Alert rules**:

| Alert | Threshold Normal | Threshold Demo |
|-------|-----------------|----------------|
| CPU | IS ABOVE 85 | IS ABOVE 20 |
| Memory | IS ABOVE 90 | IS ABOVE 20 |
| Disk | IS ABOVE 80 | IS ABOVE 15 |

Kembalikan ke nilai normal setelah mendapat screenshot notifikasi Discord.

### Screenshot: CPU Naik Saat Stress Test

> 📸 *[Screenshot: grafik CPU di Grafana menunjukkan lonjakan saat stress test dijalankan]*

### Screenshot: Alert Terpicu di Grafana

> 📸 *[Screenshot: alert rule berubah menjadi "Firing" di halaman Alert rules Grafana]*

### Screenshot: Notifikasi Discord Saat Alert

> 📸 *[Screenshot: pesan Discord dari Grafana webhook saat CPU tinggi]*

---

## 13. Kesimpulan

Sistem monitoring menggunakan **Prometheus** dan **Grafana** berhasil dibangun di VM Azure dengan IP publik `57.158.27.100`, dengan fitur lengkap:

### ✅ Fitur Utama (Wajib)
- [x] **Prometheus** terinstal dan berjalan sebagai monitoring & metrics collection
- [x] **Grafana** terinstal dan berjalan sebagai tools visualisasi
- [x] **Node Exporter** dikonfigurasi dan di-scrape oleh Prometheus
- [x] **Custom dashboard** dibuat manual di Grafana (tanpa template bawaan) dengan 7 panel: CPU Tren, CPU Gauge, Memory, Disk, Network, Uptime, Load Average

### ✅ Fitur Opsional (Bonus)
- [x] **Alert rules** dikonfigurasi untuk CPU, Memory, Disk, dan Instance Down
- [x] **Discord Webhook** terintegrasi sebagai notifikasi alert
- [x] **Query PromQL kompleks** digunakan: `rate()`, `avg_over_time()`, `max_over_time()`, `predict_linear()`
- [x] **Visualisasi variatif**: Time series, Gauge, Bar gauge, Stat, Stacked area

### Manfaat Sistem Ini

1. **Early Warning System** — mendeteksi masalah sebelum berdampak ke pengguna
2. **Real-time Monitoring** — data diupdate setiap 15 detik
3. **Predictive Analysis** — `predict_linear()` bisa memprediksi kapan disk akan penuh
4. **Zero Cost** — semua tools open source (Prometheus, Grafana, Node Exporter)

---

## 📚 Referensi

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter GitHub](https://github.com/prometheus/node_exporter)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Grafana Alerting Docs](https://grafana.com/docs/grafana/latest/alerting/)
- [Discord Webhooks](https://discord.com/developers/docs/resources/webhook)
- [Oprec NCC Lab Pertemuan 1](https://github.com/ncclaboratory18/Oprec_2026_Pertemuan_1)
- [Oprec NCC Lab Pertemuan 2](https://github.com/ncclaboratory18/Oprec_2026_Pertemuan_2)

---

> 📝 **Dibuat untuk keperluan Open Recruitment NCC Laboratory 2026 — Pertemuan 3**
> VM Azure Public IP: `57.158.27.100`
