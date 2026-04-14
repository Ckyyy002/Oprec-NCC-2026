from fastapi import FastAPI
from datetime import datetime, timezone

app = FastAPI(title="Health Check", version="1.0.0")


@app.get("/")
def root():
    return {
        "service": "OPREC NCC 2026 Health Check",
        "status": "running",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/health")
def health_check():
    return {
        "status": "ok",
        "uptime": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }