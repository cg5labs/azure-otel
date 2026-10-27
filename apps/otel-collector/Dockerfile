FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && mkdir -p /app/data /app/logs /app/certs/ca /app/certs/client \
    && chown 65532:65532 /app/data /app/logs

COPY --chown=65532:65532 law_otel_adapter/ ./law_otel_adapter/
COPY --chown=65532:65532 config.yaml ./

USER 65532:65532
EXPOSE 8080
CMD ["python", "-m", "law_otel_adapter.main", "--config", "/app/config.yaml"]
