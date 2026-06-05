# 📊 Prometheus & Grafana — Monitoring Stack

## Overview

| Tool | Peran |
|---|---|
| **Prometheus** | Time-series database untuk scraping & penyimpanan metrik |
| **Grafana** | Platform visualisasi dan alerting berbasis dashboard |
| **Alertmanager** | Routing dan manajemen alert dari Prometheus |
| **Node Exporter** | Exporter metrik sistem (CPU, RAM, disk, network) |

---

## Arsitektur

```
┌──────────────────────────────────────────────────────────┐
│                      Targets / Exporters                 │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Node Export │  │  App /metrics│  │  cAdvisor       │ │
│  └──────┬──────┘  └──────┬───────┘  └────────┬────────┘ │
└─────────┼────────────────┼───────────────────┼──────────┘
          │   Scrape (Pull)│                   │
          ▼                ▼                   ▼
┌─────────────────────────────────────────────────────┐
│                    Prometheus                        │
│   ┌─────────────┐     ┌──────────────────────────┐  │
│   │  TSDB Store │     │  Alerting Rules Engine   │  │
│   └─────────────┘     └──────────────┬───────────┘  │
└───────────────────────────────────────┼─────────────┘
                                        │
                              ┌─────────▼──────────┐
                              │    Alertmanager     │
                              │  ┌───────────────┐  │
                              │  │ Discord/Email │  │
                              │  └───────────────┘  │
                              └─────────────────────┘
                                        │
┌───────────────────────────────────────▼─────────────┐
│                     Grafana                          │
│   ┌────────────────────────────────────────────────┐│
│   │            Dashboard & Visualization           ││
│   └────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

---

## Instalasi via Docker Compose

```yaml
version: '3.9'

services:

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    networks:
      - monitoring
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager:/etc/alertmanager
    networks:
      - monitoring
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    networks:
      - monitoring
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    networks:
      - monitoring
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    ports:
      - "8081:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    networks:
      - monitoring
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:

networks:
  monitoring:
    driver: bridge
```

---

## Konfigurasi Prometheus

### `prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - "alert_rules.yml"

scrape_configs:

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'myapp'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['myapp:3000']
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
```

---

## Alert Rules

### `prometheus/alert_rules.yml`

```yaml
groups:
  - name: infrastructure
    rules:

      # CPU usage tinggi
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "CPU usage tinggi di {{ $labels.instance }}"
          description: "CPU usage: {{ $value | printf \"%.2f\" }}%"

      # Memory hampir penuh
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Memory usage tinggi di {{ $labels.instance }}"
          description: "Memory usage: {{ $value | printf \"%.2f\" }}%"

      # Disk hampir penuh
      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Disk space kritis di {{ $labels.instance }}"
          description: "Sisa disk: {{ $value | printf \"%.2f\" }}%"

      # Instance down
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} down"
          description: "Job {{ $labels.job }} tidak dapat di-scrape"

  - name: application
    rules:

      # HTTP error rate tinggi
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Error rate tinggi di {{ $labels.instance }}"
          description: "Error rate: {{ $value | printf \"%.2%\" }}"

      # Response time lambat
      - alert: SlowResponseTime
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Response time lambat di {{ $labels.instance }}"
          description: "P95 latency: {{ $value | printf \"%.2f\" }}s"
```

---

## Konfigurasi Alertmanager

### `alertmanager/alertmanager.yml`

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'instance']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
    - match:
        severity: warning
      receiver: 'warning-alerts'

receivers:
  - name: 'default'
    discord_configs:
      - webhook_url: 'https://discord.com/api/webhooks/xxx/yyy'
        title: '🔔 Alert: {{ .GroupLabels.alertname }}'
        message: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'critical-alerts'
    discord_configs:
      - webhook_url: 'https://discord.com/api/webhooks/xxx/yyy'
        title: '🔴 CRITICAL: {{ .GroupLabels.alertname }}'
        message: '{{ range .Alerts }}**{{ .Annotations.summary }}**\n{{ .Annotations.description }}{{ end }}'
    email_configs:
      - to: 'devops@company.com'
        from: 'alertmanager@company.com'
        smarthost: 'smtp.gmail.com:587'

  - name: 'warning-alerts'
    discord_configs:
      - webhook_url: 'https://discord.com/api/webhooks/xxx/yyy'
        title: '⚠️ WARNING: {{ .GroupLabels.alertname }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

---

## Prometheus Query Language (PromQL)

### Query Dasar

```promql
# CPU usage per core
rate(node_cpu_seconds_total{mode!="idle"}[5m])

# Total memory usage (%)
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Network traffic masuk (bytes/sec)
rate(node_network_receive_bytes_total{device="eth0"}[5m])

# Jumlah request HTTP per menit
rate(http_requests_total[1m]) * 60

# P99 latency
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# Container CPU usage
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100
```

---

## Grafana Dashboard

### Provisioning Datasource Otomatis

**`grafana/provisioning/datasources/prometheus.yml`**

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

### Dashboard yang Direkomendasikan

| Dashboard ID | Nama | Deskripsi |
|---|---|---|
| `1860` | Node Exporter Full | Metrik lengkap server |
| `893` | Docker Monitoring | Metrik container Docker |
| `14282` | cAdvisor | Container resource usage |
| `4701` | JVM Micrometer | Metrik Java/Spring Boot |

Import via: **Grafana → Dashboards → Import → Masukkan ID**

---

## Instrumentasi Aplikasi (Node.js)

```typescript
import { Registry, Counter, Histogram, collectDefaultMetrics } from 'prom-client';
import express from 'express';

const register = new Registry();
collectDefaultMetrics({ register });

// Counter untuk HTTP requests
const httpRequestsTotal = new Counter({
    name: 'http_requests_total',
    help: 'Total jumlah HTTP requests',
    labelNames: ['method', 'route', 'status'],
    registers: [register],
});

// Histogram untuk response time
const httpRequestDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'Durasi HTTP request dalam detik',
    labelNames: ['method', 'route'],
    buckets: [0.1, 0.3, 0.5, 1, 2, 5],
    registers: [register],
});

// Middleware
app.use((req, res, next) => {
    const end = httpRequestDuration.startTimer({ method: req.method, route: req.path });
    res.on('finish', () => {
        httpRequestsTotal.inc({ method: req.method, route: req.path, status: res.statusCode });
        end();
    });
    next();
});

// Endpoint metrics
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', register.contentType);
    res.send(await register.metrics());
});
```

---

## Troubleshooting

| Masalah | Solusi |
|---|---|
| Target di Prometheus "DOWN" | Cek jaringan Docker, pastikan service dalam network yang sama |
| Alert tidak terkirim | Cek Alertmanager UI di port 9093 → Status → Config |
| Grafana tidak bisa query Prometheus | Pastikan datasource URL menggunakan nama service Docker |
| Metrik tidak muncul | Cek `curl http://localhost:9090/api/v1/targets` |

---

## Referensi

- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)
- [PromQL Cheatsheet](https://promlabs.com/promql-cheat-sheet/)
- [Awesome Prometheus Alerts](https://awesome-prometheus-alerts.grep.to/)
