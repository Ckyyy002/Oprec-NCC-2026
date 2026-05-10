# 📡 Materi: Prometheus & Grafana — Sistem Monitoring Modern

> **Oprec NCC Laboratory 2026 — Pertemuan 3**

---

## 📋 Daftar Isi

1. [Apa itu Monitoring?](#1-apa-itu-monitoring)
2. [Prometheus](#2-prometheus)
3. [Node Exporter](#3-node-exporter)
4. [PromQL — Bahasa Query Prometheus](#4-promql--bahasa-query-prometheus)
5. [Grafana](#5-grafana)
6. [Alerting](#6-alerting)
7. [Arsitektur Sistem di Project Ini](#7-arsitektur-sistem-di-project-ini)
8. [Use Case di Dunia Kerja Nyata](#8-use-case-di-dunia-kerja-nyata)
9. [Perbandingan dengan Tools Lain](#9-perbandingan-dengan-tools-lain)
10. [Rangkuman](#10-rangkuman)

---

## 1. Apa itu Monitoring?

Monitoring adalah proses **mengamati kondisi sistem secara terus-menerus** untuk memastikan semuanya berjalan normal, mendeteksi masalah sedini mungkin, dan memiliki data historis untuk analisis.

Tanpa monitoring, tim engineering bekerja seperti **mengemudi dengan mata tertutup** — tidak tahu ada masalah sampai pengguna komplain atau sistem benar-benar mati.

### Tiga Pilar Observability

Dalam dunia DevOps dan SRE (Site Reliability Engineering), monitoring adalah bagian dari konsep yang lebih luas yang disebut **Observability** (kemampuan untuk memahami kondisi internal sistem dari output eksternalnya). Observability terdiri dari tiga pilar:

```
┌─────────────────────────────────────────────────────┐
│                   OBSERVABILITY                      │
│                                                      │
│   ┌──────────┐   ┌──────────┐   ┌──────────────┐   │
│   │ METRICS  │   │  LOGS    │   │   TRACES     │   │
│   │          │   │          │   │              │   │
│   │ Angka    │   │ Teks     │   │ Jejak alur   │   │
│   │ numerik  │   │ kejadian │   │ request      │   │
│   │ dari     │   │ yang     │   │ antar        │   │
│   │ waktu ke │   │ terjadi  │   │ service      │   │
│   │ waktu    │   │ di sistem│   │              │   │
│   │          │   │          │   │              │   │
│   │ Tool:    │   │ Tool:    │   │ Tool:        │   │
│   │Prometheus│   │ Loki,    │   │ Jaeger,      │   │
│   │          │   │ ELK Stack│   │ Tempo        │   │
│   └──────────┘   └──────────┘   └──────────────┘   │
└─────────────────────────────────────────────────────┘
```

Di project ini, fokus kita adalah pada **Metrics** menggunakan Prometheus dan Grafana.

### Jenis-jenis Metrics

| Jenis | Deskripsi | Contoh |
|-------|-----------|--------|
| **Counter** | Nilai yang hanya naik, tidak pernah turun | Total request, total error |
| **Gauge** | Nilai yang bisa naik dan turun | CPU usage, memory usage, jumlah koneksi aktif |
| **Histogram** | Distribusi nilai dalam bucket | Durasi response time (berapa request < 100ms, < 500ms, dll) |
| **Summary** | Ringkasan statistik (percentile) | p50, p90, p99 response time |

---

## 2. Prometheus

### Apa itu Prometheus?

Prometheus adalah **open-source monitoring dan alerting toolkit** yang awalnya dibuat oleh SoundCloud pada 2012, kemudian didonasikan ke Cloud Native Computing Foundation (CNCF) pada 2016. Saat ini Prometheus adalah standar de-facto untuk monitoring di ekosistem cloud-native dan Kubernetes.

### Model Kerja: Pull vs Push

Hal yang membedakan Prometheus dari tools monitoring lama (seperti Nagios) adalah modelnya yang menggunakan **pull** (tarik), bukan push (dorong):

```
PUSH MODEL (lama):
[Aplikasi] ──────────────────────► [Monitoring Server]
           "Saya kirim data ke kamu"

PULL MODEL (Prometheus):
[Prometheus] ──scrape──► [Aplikasi / Exporter]
             "Saya ambil data dari kamu setiap N detik"
```

**Keuntungan Pull Model:**
- Prometheus yang mengontrol kapan dan seberapa sering data diambil
- Lebih mudah mendeteksi jika target mati (tidak ada data = target down)
- Tidak perlu konfigurasi di sisi aplikasi untuk "ke mana mengirim data"
- Lebih aman — target tidak perlu tahu alamat monitoring server

### Komponen Internal Prometheus

```
┌─────────────────────────────────────────────────────────────┐
│                        PROMETHEUS                            │
│                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │  Retrieval  │    │    TSDB       │    │  HTTP Server  │  │
│  │  (Scraper)  │───►│ (Time Series │───►│  (Query API)  │  │
│  │             │    │   Database)  │    │               │  │
│  └─────────────┘    └──────────────┘    └───────────────┘  │
│         │                                       ▲           │
│         │ scrape setiap                         │           │
│         │ 15 detik                           PromQL         │
│         ▼                                    query          │
│  ┌─────────────┐                               │           │
│  │ Service     │                        ┌──────┴──────┐    │
│  │ Discovery   │                        │   Grafana   │    │
│  │ (static,    │                        │   / Client  │    │
│  │  K8s, dll)  │                        └─────────────┘    │
│  └─────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

### Time Series Database (TSDB)

Prometheus menyimpan data dalam **TSDB** — database khusus yang dioptimalkan untuk data time-series (data yang berubah seiring waktu). Setiap data point disimpan dalam format:

```
metric_name{label1="value1", label2="value2"} value timestamp

Contoh:
node_cpu_seconds_total{cpu="0", mode="idle"} 12345.67 1715000000
node_memory_MemAvailable_bytes{} 5234567890 1715000000
```

Data disimpan dalam bentuk **blok** per 2 jam, lalu dikompresi. Default retensi adalah 15 hari (bisa dikonfigurasi).

### Konfigurasi Scraping

Di file `prometheus.yml`, kita mendefinisikan **target** mana yang akan di-scrape:

```yaml
scrape_configs:
  - job_name: "node_exporter"
    scrape_interval: 15s      # Ambil data setiap 15 detik
    scrape_timeout: 10s       # Timeout jika target tidak merespons
    static_configs:
      - targets: ["localhost:9100"]
        labels:               # Label tambahan untuk semua metrics dari target ini
          environment: "production"
          datacenter: "azure-eastus"
```

### Label — Kunci Fleksibilitas Prometheus

Label adalah **key-value pair** yang melekat pada setiap metrics. Label inilah yang membuat Prometheus sangat fleksibel:

```
# Tanpa label — hanya tahu total CPU
node_cpu_seconds_total = 12345

# Dengan label — bisa filter dan aggregate
node_cpu_seconds_total{cpu="0", mode="user"}   = 1234
node_cpu_seconds_total{cpu="0", mode="system"} = 456
node_cpu_seconds_total{cpu="1", mode="user"}   = 1189
node_cpu_seconds_total{cpu="1", mode="idle"}   = 9000
```

Dengan label, satu metrics bisa menjawab banyak pertanyaan: CPU core berapa? Mode apa? Dari server mana?

---

## 3. Node Exporter

### Apa itu Exporter?

Prometheus tidak bisa langsung membaca metrics dari sistem operasi. Di sinilah **exporter** berperan — program kecil yang **"menerjemahkan"** data dari sumber aslinya ke format yang bisa dibaca Prometheus, lalu mengeksposnya melalui HTTP endpoint `/metrics`.

```
[Sistem Operasi]                [Node Exporter]           [Prometheus]
  /proc/cpuinfo    ──────────►  /metrics endpoint  ◄──────  scrape
  /proc/meminfo                  (format teks)
  /sys/block/...
```

### Metrics yang Disediakan Node Exporter

Node Exporter mengekspos ratusan metrics. Berikut yang paling penting:

**CPU:**
```
node_cpu_seconds_total{cpu, mode}     # Waktu CPU dalam setiap mode (user, system, idle, iowait, steal, ...)
node_load1                             # Load average 1 menit
node_load5                             # Load average 5 menit
node_load15                            # Load average 15 menit
```

**Memory:**
```
node_memory_MemTotal_bytes             # Total RAM
node_memory_MemAvailable_bytes         # RAM yang tersedia
node_memory_MemFree_bytes              # RAM yang benar-benar kosong
node_memory_Cached_bytes               # RAM untuk cache
node_memory_Buffers_bytes              # RAM untuk buffer
```

**Disk:**
```
node_filesystem_size_bytes{mountpoint} # Total kapasitas filesystem
node_filesystem_avail_bytes{mountpoint}# Ruang yang tersedia
node_disk_read_bytes_total{device}     # Total byte yang dibaca dari disk
node_disk_written_bytes_total{device}  # Total byte yang ditulis ke disk
node_disk_reads_completed_total        # Total operasi baca selesai
node_disk_writes_completed_total       # Total operasi tulis selesai
```

**Network:**
```
node_network_receive_bytes_total{device}   # Total byte diterima
node_network_transmit_bytes_total{device}  # Total byte dikirim
node_network_receive_errs_total            # Error saat menerima
node_network_transmit_errs_total           # Error saat mengirim
```

**Sistem:**
```
node_boot_time_seconds                 # Waktu boot sistem (Unix timestamp)
up                                     # 1 jika target up, 0 jika down
```

### Exporter Lain yang Populer

Node Exporter hanya untuk Linux. Ada ratusan exporter untuk berbagai kebutuhan:

| Exporter | Kegunaan |
|----------|----------|
| **blackbox_exporter** | Probe HTTP, TCP, ICMP — cek apakah endpoint bisa diakses |
| **mysqld_exporter** | Metrics database MySQL/MariaDB |
| **postgres_exporter** | Metrics database PostgreSQL |
| **redis_exporter** | Metrics Redis |
| **nginx-prometheus-exporter** | Metrics Nginx web server |
| **cadvisor** | Metrics Docker container |
| **kube-state-metrics** | Metrics state objek Kubernetes |
| **windows_exporter** | Metrics untuk Windows Server |

---

## 4. PromQL — Bahasa Query Prometheus

PromQL (Prometheus Query Language) adalah bahasa query khusus untuk mengambil dan mengolah data time-series dari Prometheus. Memahami PromQL adalah kunci untuk membuat dashboard dan alert yang bermakna.

### Tipe Data di PromQL

**1. Instant Vector** — Nilai terbaru dari setiap time series yang cocok:
```promql
node_memory_MemAvailable_bytes
# Mengembalikan satu nilai per time series, pada saat ini
```

**2. Range Vector** — Nilai dalam rentang waktu tertentu (dibutuhkan oleh fungsi seperti `rate()`):
```promql
node_cpu_seconds_total[5m]
# Mengembalikan semua nilai dalam 5 menit terakhir
```

**3. Scalar** — Angka tunggal:
```promql
1024 * 1024
```

### Selector dan Filter

```promql
# Pilih metric dengan label tertentu (=)
node_cpu_seconds_total{mode="idle"}

# Pilih metric yang labelnya BUKAN nilai tertentu (!=)
node_network_receive_bytes_total{device!="lo"}

# Pilih metric dengan label yang cocok regex (=~)
node_cpu_seconds_total{mode=~"user|system"}

# Pilih metric dengan label yang TIDAK cocok regex (!~)
node_filesystem_avail_bytes{fstype!~"tmpfs|devtmpfs"}
```

### Fungsi-Fungsi Penting

**`rate()`** — Hitung kecepatan perubahan per detik (untuk Counter):
```promql
# Kecepatan CPU dalam mode user, rata-rata 5 menit terakhir
rate(node_cpu_seconds_total{mode="user"}[5m])
```
> ⚠️ `rate()` hanya untuk **Counter** (nilai yang terus naik). Jangan gunakan untuk Gauge.

**`irate()`** — Seperti `rate()` tapi menggunakan 2 data point terakhir (lebih responsif tapi tidak stabil):
```promql
irate(node_cpu_seconds_total{mode="user"}[5m])
```

**`avg()`, `sum()`, `min()`, `max()`** — Agregasi:
```promql
# Rata-rata CPU usage semua core
avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))

# Total network traffic semua interface
sum(rate(node_network_receive_bytes_total[5m]))
```

**`by` dan `without`** — Agregasi dengan pengelompokan:
```promql
# Rata-rata CPU per mode (kelompokkan berdasarkan label mode)
avg by (mode) (rate(node_cpu_seconds_total[5m]))

# Total traffic per device
sum by (device) (rate(node_network_receive_bytes_total[5m]))
```

**`predict_linear()`** — Prediksi nilai di masa depan berdasarkan tren:
```promql
# Prediksi ruang disk 24 jam ke depan berdasarkan tren 6 jam terakhir
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[6h], 24*3600)
```

**`avg_over_time()`, `max_over_time()`** — Agregasi dalam range waktu:
```promql
# Rata-rata CPU dalam 10 menit, dihitung tiap 1 menit
avg_over_time(rate(node_cpu_seconds_total{mode="idle"}[5m])[10m:1m])

# Puncak tertinggi network dalam 1 jam
max_over_time(rate(node_network_receive_bytes_total[5m])[1h:5m])
```

### Contoh Query Lengkap

```promql
# CPU Usage (%) — yang paling sering digunakan
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory Usage (%)
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Disk Usage (%)
(1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

# Network receive dalam KB/s
rate(node_network_receive_bytes_total{device!="lo"}[5m]) / 1024
```

---

## 5. Grafana

### Apa itu Grafana?

Grafana adalah platform **open-source untuk visualisasi dan analisis data**. Grafana tidak menyimpan data sendiri — ia hanya menghubungkan ke berbagai **data source** (Prometheus, InfluxDB, MySQL, Elasticsearch, dll) dan menampilkan datanya dalam bentuk dashboard interaktif.

```
[Prometheus] ──────┐
[MySQL]      ──────┤──► [Grafana] ──► Dashboard, Alert, Report
[Loki]       ──────┘
```

### Komponen Utama Grafana

**Dashboard** — Kumpulan panel dalam satu halaman. Bisa berisi banyak panel dengan tipe berbeda-beda.

**Panel** — Unit visualisasi tunggal. Setiap panel memiliki satu atau lebih query dan dikonfigurasi untuk menampilkan data dengan cara tertentu.

**Data Source** — Koneksi ke sumber data (Prometheus, database, dll).

**Alert Rules** — Aturan yang dievaluasi secara berkala; jika kondisi terpenuhi, notifikasi dikirim.

**Contact Points** — Tujuan notifikasi alert (Discord, Slack, Email, PagerDuty, dll).

### Tipe Panel dan Kapan Menggunakannya

| Tipe Panel | Kapan Digunakan | Contoh |
|------------|-----------------|--------|
| **Time series** | Data yang berubah seiring waktu, ingin melihat tren | CPU usage, network traffic |
| **Gauge** | Nilai saat ini dalam rentang min-max, status sekilas | CPU % sekarang, memory % |
| **Bar gauge** | Seperti gauge tapi berbentuk progress bar | Disk usage per mountpoint |
| **Stat** | Satu angka besar yang penting | Uptime, jumlah server aktif |
| **Table** | Data tabular dengan banyak kolom | Daftar semua server dan statusnya |
| **Heatmap** | Distribusi nilai, pola densitas | Distribusi response time |
| **Pie chart** | Proporsi/komposisi | Pembagian traffic per region |
| **Histogram** | Distribusi frekuensi | Sebaran response time request |

### Fitur Penting Grafana

**Variables** — Membuat dashboard dinamis. Misalnya, dropdown untuk memilih server mana yang ingin ditampilkan:
```
Variable: $instance
Query: label_values(node_cpu_seconds_total, instance)
# Otomatis mengisi dropdown dengan semua nilai label instance
```

**Annotations** — Menandai event penting di grafik (deploy, incident, maintenance) sehingga bisa dikorelasikan dengan perubahan metrics.

**Templating** — Reuse dashboard untuk berbagai environment (dev, staging, production) hanya dengan mengganti variable.

**Playlist** — Rotasi otomatis antar dashboard, berguna untuk display di layar TV ruang NOC.

---

## 6. Alerting

### Konsep Alerting

Alerting adalah mekanisme untuk **secara otomatis memberitahu tim** ketika kondisi tertentu terpenuhi, tanpa harus terus-menerus memantau dashboard secara manual.

### Siklus Hidup Alert di Grafana

```
Normal ──(kondisi terpenuhi)──► Pending ──(durasi "for" tercapai)──► Firing
  ▲                                                                      │
  └─────────────────(kondisi tidak lagi terpenuhi)──────────────────────┘
                                                                Resolved
```

- **Normal** — Kondisi tidak terpenuhi, tidak ada masalah
- **Pending** — Kondisi terpenuhi, tapi belum cukup lama (menghindari false alert dari lonjakan sesaat)
- **Firing** — Alert aktif, notifikasi dikirim
- **Resolved** — Kondisi kembali normal, notifikasi "resolved" dikirim

### Komponen Alert Rule

```yaml
# Contoh alert rule
nama: High CPU Usage
query: 100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
kondisi: IS ABOVE 85        # Threshold
for: 2m                     # Harus terpenuhi selama 2 menit terus-menerus
                             # (mencegah false positive dari spike sesaat)
labels:
  severity: critical
annotations:
  summary: CPU usage tinggi
  description: CPU usage saat ini {{ $value }}%
```

### Kenapa "for" Itu Penting?

Tanpa `for`, setiap lonjakan CPU sesaat (bahkan 1 detik) akan langsung memicu alert dan membanjiri Discord/email. Dengan `for: 2m`, Grafana baru mengirim alert jika kondisi bertahan **terus-menerus selama 2 menit** — mengurangi false positive secara signifikan.

### Notification Policy — Routing Alert

Grafana memungkinkan routing alert yang berbeda ke tujuan berbeda berdasarkan label:

```
Default Policy ──► Discord (semua alert)
    │
    ├── severity=critical ──► PagerDuty (on-call engineer dihubungi)
    └── team=database ──► Slack #db-alerts (hanya tim database)
```

---

## 7. Arsitektur Sistem di Project Ini

Berikut penjelasan detail mengapa arsitektur di project ini dirancang demikian:

### Satu VM, Semua Komponen

```
[VM Azure — 57.158.27.100]
│
├── Node Exporter (:9100) — bind 127.0.0.1
│     Alasan: Tidak perlu diakses dari luar.
│     Hanya Prometheus (di VM yang sama) yang perlu scrape.
│
├── Prometheus (:9090) — bind 127.0.0.1
│     Alasan: Prometheus UI tidak butuh diakses publik.
│     Grafana (di VM yang sama) query langsung via localhost.
│     Mengekspos ke publik = risiko keamanan (data sensitif).
│
└── Grafana (:3000) — bind 0.0.0.0 (publik)
      Alasan: Ini satu-satunya interface yang perlu diakses
      oleh tim/pengguna dari browser.
```

### Mengapa Tidak Memakai Template Dashboard?

Membuat dashboard dari nol menggunakan PromQL manual memberikan pemahaman yang jauh lebih dalam tentang:
- Apa arti setiap metrics
- Bagaimana cara menghitung persentase dari raw data
- Bagaimana `rate()`, `avg()`, dan fungsi lain bekerja

Template seperti ID 1860 (Node Exporter Full) memang bagus untuk production, tapi tidak mengajarkan cara kerjanya.

---

## 8. Use Case di Dunia Kerja Nyata

Berikut adalah bagaimana Prometheus dan Grafana digunakan di perusahaan-perusahaan nyata:

---

### 8.1 E-Commerce — Monitoring Saat Flash Sale

**Skenario:** Tokopedia, Shopee, atau Lazada memiliki traffic yang melonjak drastis saat flash sale. Tim engineer perlu tahu secara real-time apakah infrastruktur mampu menangani beban.

**Metrics yang Dipantau:**
- Request per second (RPS) ke setiap service
- Response time (p50, p90, p99) — apakah checkout lambat?
- Error rate — berapa persen request yang gagal?
- CPU & memory semua server
- Jumlah koneksi database aktif

**Alert yang Dipasang:**
- Error rate > 1% → alert ke Slack tim engineering
- Response time p99 > 2 detik → alert ke PagerDuty (on-call engineer dihubungi)
- CPU > 80% lebih dari 5 menit → auto-scaling dipicu

**Dashboard yang Dibuat:**
- Dashboard "Flash Sale Overview" yang ditampilkan di layar TV besar di ruang NOC
- Panel hitungan RPS real-time, error rate, dan server health
- Anotasi otomatis saat ada deployment atau incident

---

### 8.2 Startup SaaS — Multi-Tenant Monitoring

**Skenario:** Sebuah startup yang menyediakan layanan SaaS (misalnya project management tool) perlu memantau performa untuk ratusan customer (tenant) secara terpisah.

**Cara Implementasi dengan Label:**
```promql
# Metrics dengan label tenant
http_requests_total{tenant="company_a", endpoint="/api/tasks"} = 1234
http_requests_total{tenant="company_b", endpoint="/api/tasks"} = 567

# Query: error rate per tenant
rate(http_errors_total{tenant="company_a"}[5m]) /
rate(http_requests_total{tenant="company_a"}[5m]) * 100
```

**Grafana Variables:**
- Dropdown `$tenant` di dashboard
- Satu dashboard bisa digunakan untuk memantau semua tenant hanya dengan mengganti dropdown
- Customer support bisa langsung lihat kondisi tenant yang sedang komplain

---

### 8.3 Perbankan — Monitoring Kepatuhan SLA

**Skenario:** Bank digital wajib memastikan uptime dan response time sesuai SLA (Service Level Agreement) yang dijanjikan ke nasabah dan regulator (OJK).

**SLI (Service Level Indicator)** — Metric yang diukur:
```
Availability = (total_time - downtime) / total_time * 100
Latency P99  = 99% request selesai dalam waktu X ms
Error Rate   = error / total_request * 100
```

**SLO (Service Level Objective)** — Target yang harus dicapai:
```
Availability ≥ 99.9% (maksimal 8.7 jam downtime per tahun)
Latency P99  ≤ 500ms
Error Rate   ≤ 0.1%
```

**Alert Berbasis Error Budget:**
```promql
# Sisa error budget (berapa persen "jatah error" yang masih tersisa bulan ini)
1 - (
  sum(rate(http_errors_total[30d])) /
  sum(rate(http_requests_total[30d]))
) / 0.001   # 0.001 = 0.1% error rate target
```

Jika error budget hampir habis, tim SRE segera freeze deployment dan fokus stabilitas.

---

### 8.4 Media Streaming — Monitoring Video CDN

**Skenario:** Platform streaming (seperti Vidio atau Mola) memantau kualitas delivery video ke jutaan penonton.

**Metrics yang Dipantau:**
- Bandwidth per CDN node per region
- Buffer ratio (berapa persen penonton yang mengalami buffering)
- Bitrate switching events (berapa kali video turun kualitasnya)
- CDN cache hit ratio (berapa persen video disajikan dari cache, bukan origin)

**Alert Contoh:**
```promql
# Alert jika cache hit ratio turun di bawah 80% (beban ke origin server naik)
cdn_cache_hit_ratio{region="id-java"} < 0.80

# Alert jika bandwidth di atas 90% kapasitas CDN node
cdn_bandwidth_usage_bytes / cdn_bandwidth_capacity_bytes > 0.90
```

---

### 8.5 Kubernetes Cluster — Monitoring Container Orchestration

**Skenario:** Perusahaan yang sudah menggunakan Kubernetes untuk deploy ratusan microservice membutuhkan monitoring yang lebih granular dari sekadar server.

**Stack Monitoring Kubernetes:**
```
[kube-state-metrics] ──► kondisi objek K8s (pod, deployment, node)
[cAdvisor]           ──► resource usage per container
[node_exporter]      ──► resource usage per node (VM)
         │
         └──► [Prometheus] ──► [Grafana]
```

**Metrics Penting di Kubernetes:**
```promql
# Pod yang restart berkali-kali (tanda ada masalah)
kube_pod_container_status_restarts_total > 5

# Deployment yang tidak memiliki pod running
kube_deployment_status_replicas_available == 0

# Node yang hampir kehabisan memory
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.90
```

---

### 8.6 DevOps Pipeline — Monitoring CI/CD

**Skenario:** Tim engineering memantau kesehatan pipeline CI/CD (GitHub Actions, GitLab CI, Jenkins) untuk memastikan proses build dan deploy berjalan lancar.

**Metrics yang Dipantau:**
- Build duration — apakah pipeline semakin lama?
- Build success rate — berapa persen pipeline gagal?
- Queue time — berapa lama job menunggu sebelum dieksekusi?
- Deploy frequency — seberapa sering tim melakukan deploy (DORA metrics)

**Dashboard DORA Metrics:**
```
Deployment Frequency    → seberapa sering deploy (lebih sering = lebih baik)
Lead Time for Changes   → waktu dari commit ke production
Change Failure Rate     → berapa persen deploy menyebabkan masalah
Time to Restore         → berapa lama memulihkan sistem saat ada incident
```

---

### 8.7 IoT & Manufaktur — Monitoring Mesin Pabrik

**Skenario:** Pabrik dengan ratusan mesin produksi menggunakan sensor IoT untuk memantau kondisi mesin secara real-time dan mencegah kerusakan (predictive maintenance).

**Data dari Sensor → Prometheus:**
```
machine_temperature_celsius{machine_id="CNC-01", location="floor-a"} = 78.5
machine_vibration_hz{machine_id="CNC-01"}                            = 45.2
machine_power_consumption_watts{machine_id="CNC-01"}                 = 3200
machine_oil_pressure_bar{machine_id="CNC-01"}                        = 4.8
```

**Alert Predictive Maintenance:**
```promql
# Temperatur naik lebih dari 10°C dalam 30 menit
delta(machine_temperature_celsius[30m]) > 10

# Prediksi mesin akan overheat dalam 2 jam
predict_linear(machine_temperature_celsius[1h], 2*3600) > 90
```

Sebelum mesin rusak, teknisi sudah mendapat notifikasi dan bisa melakukan perawatan preventif — menghemat biaya perbaikan dan downtime produksi.

---

## 9. Perbandingan dengan Tools Lain

### Prometheus vs Tools Monitoring Lain

| Aspek | Prometheus | Datadog | New Relic | Nagios |
|-------|------------|---------|-----------|--------|
| **Model** | Pull | Push/Pull | Push | Pull |
| **Biaya** | Gratis (open source) | Berbayar ($15+/host/bulan) | Berbayar | Gratis (core) |
| **Setup** | Manual, fleksibel | SaaS, mudah | SaaS, mudah | Manual, rumit |
| **Cocok untuk** | Cloud-native, K8s | Enterprise, semua skala | Enterprise | On-premise legacy |
| **Storage** | Lokal (atau remote) | Cloud Datadog | Cloud New Relic | Lokal |
| **Query language** | PromQL | DQL | NRQL | - |
| **Ekosistem** | CNCF, sangat luas | Luas | Luas | Terbatas |

### Grafana vs Tools Visualisasi Lain

| Aspek | Grafana | Kibana | Datadog Dashboard | Tableau |
|-------|---------|--------|-------------------|---------|
| **Biaya** | Gratis (open source) | Gratis (ELK) | Berbayar | Berbayar |
| **Data Source** | Sangat banyak (60+) | Elasticsearch saja | Datadog saja | Banyak (fokus BI) |
| **Alerting** | Ya | Ya (terbatas) | Ya | Tidak |
| **Cocok untuk** | DevOps, infra monitoring | Log analytics | All-in-one monitoring | Business Intelligence |

### Kapan Memilih Prometheus + Grafana?

✅ **Pilih Prometheus + Grafana jika:**
- Budget terbatas (open source = gratis)
- Butuh kontrol penuh atas data (data tidak keluar ke vendor)
- Tim sudah familiar dengan Linux dan command line
- Menggunakan Kubernetes atau ekosistem cloud-native
- Butuh fleksibilitas tinggi dalam konfigurasi

❌ **Pertimbangkan alternatif jika:**
- Tim kecil dan tidak punya waktu untuk setup dan maintenance
- Butuh monitoring out-of-the-box tanpa konfigurasi
- Butuh dukungan (support) dari vendor
- Skala sangat besar dengan kebutuhan long-term storage (Prometheus punya limitasi storage)

---

## 10. Rangkuman

### Alur Kerja Sistem yang Dibangun

```
1. Node Exporter   → Mengekspos raw metrics OS ke /metrics endpoint
2. Prometheus      → Scrape metrics setiap 15 detik, simpan di TSDB
3. PromQL          → Bahasa query untuk mengolah data (rate, avg, predict)
4. Grafana         → Visualisasi data dalam dashboard interaktif
5. Alert Rules     → Evaluasi kondisi, trigger notifikasi jika terpenuhi
6. Discord Webhook → Terima notifikasi saat ada anomali
```

### Konsep Kunci yang Dipelajari

| Konsep | Penjelasan Singkat |
|--------|-------------------|
| **Pull model** | Prometheus aktif mengambil data dari target, bukan target yang mengirim |
| **Time series** | Data yang dicatat dengan timestamp, berubah seiring waktu |
| **Label** | Key-value pair yang melekat pada metric, membuat data bisa di-filter dan di-aggregate |
| **Exporter** | Program penerjemah antara sumber data dengan format Prometheus |
| **rate()** | Hitung kecepatan perubahan counter per detik dalam rentang waktu |
| **Gauge vs Counter** | Gauge naik-turun (CPU%), Counter hanya naik (total request) |
| **SLI/SLO** | Cara mengukur dan menargetkan kualitas layanan secara terukur |
| **Alerting** | Notifikasi otomatis berbasis kondisi metrics, dengan "for" untuk menghindari false positive |

### Relevansi di Dunia Kerja

Prometheus dan Grafana adalah skill yang **sangat dicari** di industri teknologi saat ini, terutama untuk posisi:

- **DevOps Engineer** — Setup dan maintain infrastruktur monitoring
- **Site Reliability Engineer (SRE)** — Memastikan sistem berjalan sesuai SLA
- **Backend Engineer** — Instrumentasi aplikasi dengan custom metrics
- **Platform Engineer** — Membangun platform monitoring untuk seluruh tim engineering
- **Cloud Engineer** — Monitoring resource cloud (AWS, GCP, Azure)

Hampir semua perusahaan teknologi skala menengah ke atas — dari startup hingga unicorn — menggunakan Prometheus dan Grafana, atau produk yang dibangun di atasnya (seperti Grafana Cloud, Thanos, Cortex, atau Mimir untuk skala yang lebih besar).

---

> 📝 **Dibuat untuk keperluan Open Recruitment NCC Laboratory 2026 — Pertemuan 3**
