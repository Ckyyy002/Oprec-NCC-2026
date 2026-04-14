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