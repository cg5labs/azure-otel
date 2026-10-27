# Azure Log Analytics to OTEL Adapter

## Problem and proposed approach

Create a Python application scaffold in `agentic-ai-dev/python/law-otel-adapter/`
that polls Azure Log Analytics workspaces once per minute, transforms
`ContainerLogV2` and `KubeEvents` rows into OpenTelemetry log records, and
forwards them to an authenticated OTEL Collector. Poll queries will be bounded
and time-sliced, with concurrent workers across configured workspace/table
partitions. The stated input target is over 1 GB/minute raw ingestion
aggregated across workspaces; this is a design target to benchmark, not a
throughput guarantee, due to Azure Logs Query API response and service limits.

Use a durable SQLite WAL outbox on local disk for at-least-once delivery. Store
the transformed log payload and stable source identifier before advancing that
partition's query checkpoint. A configurable overlapping lookback (five minutes
by default) will recover recently ingested/late rows; deterministic source IDs
will support downstream Collector deduplication. If the configured buffer
capacity is reached (100 GB by default), stop querying without advancing
checkpoints, keep queued records, expose/report an unhealthy state, and resume
catch-up after space is available.

## Requirements captured from the conversation

- Azure authentication uses one service principal for a configurable list of
  workspace IDs. Client secret and other credentials come from environment
  variables, not committed YAML.
- Poll `ContainerLogV2` and `KubeEvents` every 60 seconds, using five minutes of
  overlap and bounded, configurable time slices.
- Transform `TimeGenerated` to the OTEL timestamp; use `LogMessage` or
  `Message` as the body; place remaining source columns and the source table
  name in attributes.
- Prefer authenticated OTLP/gRPC with TLS and mTLS client certificate
  authentication; support OTLP/HTTP as fallback using the configured
  certificate/key/CA paths.
- Retry queued records and attach a stable source ID attribute so the Collector
  can deduplicate at-least-once deliveries.
- Use a configurable disk-buffer size with a 100 GB default. On full buffer,
  pause source fetches, do not advance the checkpoint, retain queued data, and
  report unhealthy status rather than dropping data.
- Include Docker Compose deployment with both the adapter and an OTEL Collector
  service for an end-to-end local stack. The Collector will expose OTLP/gRPC
  and OTLP/HTTP internally with mTLS; certificate material is supplied locally
  through read-only mounts and must not be committed. No Helm chart was
  requested.

## Implementation outline

1. Add application configuration, dependency manifests, a Dockerfile, Compose
   files, and a README. Document
   service-principal environment variables, workspace/table configuration,
   exporter endpoints and mTLS file paths, polling/overlap/slice settings,
   worker limits, buffer capacity, local certificate provisioning, limitations,
   and startup commands.
2. Implement typed configuration validation and a Log Analytics client using
   Azure service-principal credentials. Generate parameterized, bounded KQL
   for each workspace/table/slice. Add bounded thread-pool concurrency,
   response/row limit handling, and adaptive subdivision or explicit errors
   for oversized query slices.
3. Implement row-to-OTEL conversion with source-specific body fields, timestamp,
   workspace/table attributes, all other source columns, and a deterministic
   stable source ID for downstream deduplication.
4. Implement a SQLite WAL outbox with unique source IDs, durable batch enqueue,
   per-workspace/table checkpoints, configurable disk cap, and atomic checkpoint
   advancement only after successful enqueue. Add bounded batch retries and
   deletion only after Collector acknowledgment.
5. Implement an exporter that tries mTLS OTLP/gRPC first and falls back to
   mTLS OTLP/HTTP. Preserve at-least-once semantics and stable IDs across
   ambiguous failures. Provide a local health/readiness signal that reports
   buffer-full status.
6. Add an end-to-end Docker Compose stack with an adapter service and OTEL
   Collector service. Configure the Collector's OTLP/gRPC and OTLP/HTTP
   receivers for mTLS and a local debug/log exporter. Mount supplied cert/key/CA
   files read-only, keep secrets outside version control, and document setup.
7. Add unit tests for config validation, both table transforms, stable IDs,
   bounded query planning, checkpoint/outbox crash behavior, buffer-full
   backpressure, and exporter retry/fallback behavior. Validate the Compose
   configuration and run the available targeted tests and formatting/type
   checks.

## Notes and considerations

- Bound both worker count and query time-slice size in configuration so a large
  response cannot consume unbounded memory. Tune these values through load tests
  using representative workspace schemas and hardware.
- At more than 1 GB/minute, a 100 GB buffer represents less than 100 minutes of
  raw input before transform overhead. Measure actual on-disk OTEL payload size
  and disk headroom; alert well before the hard cap.
- Source-row fingerprinting must use stable source columns plus workspace and
  table identity. Rows identical in every available source field cannot be
  distinguished reliably; document this deduplication limitation.
- Keep TLS verification enabled. Treat log messages and event payloads as
  potentially sensitive and avoid logging credentials or full message content
  beyond the configured operational output policy.
