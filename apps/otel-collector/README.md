# Azure OpenTelemetry Collector

This directory contains a local Docker Compose deployment of the OpenTelemetry
Collector Contrib distribution. The Collector receives Azure platform logs
through Event Hubs, collects AKS managed metrics from Azure Monitor, and
accepts OTLP logs over mutual TLS. Azure infrastructure is provisioned
separately with OpenTofu; see the
[Azure foundation README](../../README.md).

The current configuration writes logs and metrics to the Collector's debug
exporter, which prints telemetry to container output. This is suitable for
local verification, not durable storage or production delivery. The configured
OTLP pipelines accept logs only; traces are not enabled.

## Data flow

| Input | Collector configuration | Output |
| --- | --- | --- |
| AKS and Container Insights logs exported from Log Analytics | Azure Event Hubs receiver; raw JSON payloads are decoded and parsed | Debug exporter |
| Managed AKS metrics | Azure Monitor receiver, queried every 60 seconds | Debug exporter |
| OTLP logs from clients | OTLP/gRPC on `4317` or OTLP/HTTP on `4318`, both protected by mutual TLS | Debug exporter |

The OTLP ports and health-check endpoint (`13133`) are exposed to the Compose
network, not published on the host. The Event Hubs receiver stores its consumer
checkpoints under `data/otel-collector-checkpoints`. Event Hubs retention is
finite, and the Terraform export rule does not backfill data from before it
became active.

## Prerequisites

- A deployed Azure environment with the AKS metrics identity, Event Hub, and
  Log Analytics export configured. The required Terraform outputs must be
  available from the OpenTofu root at `../../tf`.
- Docker with the Compose plugin.
- OpenTofu (`tofu`), Azure CLI (`az`), and OpenSSL.
- An Azure CLI login with access to the deployed subscription and AKS cluster.
- Network access to pull the Collector Contrib image.

The service principal used by the Collector needs subscription-level resource
discovery permission and **Monitoring Reader** access to the AKS resource
group. Its Listen-only Event Hubs connection string is obtained from the
OpenTofu output. The Terraform state contains the generated client secret;
protect the state and do not commit the secret or `.env`.

## Prepare the local deployment

From this directory, create the ignored local environment file and development
certificates:

```bash
cp .env.example .env
sh scripts/generate-local-certs.sh
id -g
```

Set `CERT_GID` in `.env` to the numeric group ID printed by `id -g`. The
Collector runs as a non-root user and needs group read access to its
certificates. The generated certificates are for local development only; do
not use them in production.

The environment template already sets the Event Hubs consumer group to
`$Default` and the checkpoint storage directory to
`/var/lib/otelcol/storage-v2`. The start script refreshes the Azure tenant,
client credentials, subscription, resource group, Event Hubs connection string,
and consumer group from OpenTofu outputs. Ensure the deployment has the
`enable_azure_monitor_metrics` and `enable_event_hub` features enabled.

## Start and stop with `otel.sh`

Start the Collector from this directory:

```bash
./scripts/otel.sh --start
```

`--start` runs `scripts/setenv.sh` before starting the service. The setup script
reads the required OpenTofu outputs, signs in to Azure CLI if needed, selects
the deployment subscription, verifies the tenant, and updates the local AKS
kubeconfig. It then stops and removes the existing Compose project containers,
clears and recreates the Event Hubs checkpoint directory, and refreshes the
Azure values in `.env`. The script finally starts only the
`otel-collector` Compose service.

**Important:** every `--start` clears the saved Event Hubs checkpoints. A fresh
checkpoint store can skip messages already waiting in the Event Hub, so do not
use `--start` when you need to preserve the current consumer position. The
start operation also removes other containers in this Compose project.

Follow Collector output with:

```bash
docker compose logs -f otel-collector
```

Stop the Collector without removing its container:

```bash
./scripts/otel.sh --stop
```

`--stop` leaves the checkpoint directory intact. The next `--start` will clear
it as described above. Both commands can be invoked from any working
directory; the scripts resolve the Compose and Terraform paths relative to
their own location. `--start` requires a regular `.env` file and successful
OpenTofu, Azure CLI, and Docker Compose operations. `--stop` requires Docker
Compose and the `.env` file.

## Configuration and certificates

The Collector configuration is in [`otel-collector.yaml`](otel-collector.yaml),
and the service definition is in [`compose.yaml`](compose.yaml). The Collector
uses these certificate files created by the local certificate script:

| File | Purpose |
| --- | --- |
| `certs/ca/ca.crt` | Trust anchor for mutual TLS |
| `certs/server/server.crt` | Server certificate; its DNS names include `otel-collector` and `localhost` |
| `certs/server/server.key` | Server private key |

The Azure values in `.env` are populated from the OpenTofu deployment by
`scripts/setenv.sh`. `CERT_GID` is a local setting and is preserved when that
script updates the file. Keep `.env`, private keys, and Terraform state
protected and out of source control.

To inspect runtime state or diagnose startup problems, use:

```bash
docker compose ps
docker compose logs --tail=100 otel-collector
```

The `debug` exporter writes received telemetry to these logs. Configure a
durable, appropriately secured exporter and review access controls before using
this deployment beyond local development.
