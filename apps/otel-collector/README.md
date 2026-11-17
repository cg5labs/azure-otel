# Azure OpenTelemetry Collector

This directory contains a local Docker Compose deployment of the OpenTelemetry
Collector Contrib distribution. The Collector receives Azure platform logs
through Event Hubs, collects AKS metrics from its OTLP receiver and Azure Monitor,
and accepts OTLP logs and metrics over TLS with Microsoft Entra ID token
authentication.
Client-certificate authentication is disabled. Azure infrastructure is provisioned
separately with OpenTofu; see the
[Azure foundation README](../../terraform/otel-azure/README.md). The AKS
node-local Collector agent is deployed separately with Helm and sends pod logs
and node/pod metrics to this Collector over TLS-protected OTLP/HTTP using Azure
Workload Identity.

The Collector sends OTLP and Event Hubs logs to VictoriaLogs and OTLP/Azure
Monitor metrics to VictoriaMetrics. Traces are not enabled.

## Data flow

| Input | Collector configuration | Output |
| --- | --- | --- |
| AKS and Container Insights logs exported from Log Analytics | Azure Event Hubs receiver; raw JSON payloads are decoded and parsed | VictoriaLogs via OTLP/HTTP |
| AKS node and pod metrics | Agent DaemonSet `kubeletstats` receiver; OTLP/HTTP on `4318`, protected by TLS and Entra ID OIDC token validation | VictoriaMetrics via Prometheus remote write |
| Azure Monitor AKS platform metrics | Azure Monitor receiver, queried every 60 seconds | VictoriaMetrics via Prometheus remote write |
| OTLP logs from AKS node agents and other clients | OTLP/gRPC on `4317` or OTLP/HTTP on `4318`, protected by TLS and Entra ID OIDC token validation | VictoriaLogs via OTLP/HTTP |

The OTLP/gRPC receiver port (`4317`) and OTLP/HTTP receiver port (`4318`) are
published on the Docker host at the address set by `OTEL_GRPC_BIND_ADDRESS`,
which defaults to loopback (`127.0.0.1`). The VictoriaMetrics API (`8428`),
VictoriaLogs API (`9428`), and Grafana UI (`3000`) are also bound to host loopback
only. The Collector health-check endpoint (`13133`) remains internal to the
Compose network. To receive logs and metrics from AKS, bind the OTLP ports to
the Docker host's LAN address, configure the temporary router NAT for TCP `4318`,
restrict ingress to the AKS
cluster's outbound public IP address(es), and use a server certificate whose
SAN matches the HTTPS endpoint used by AKS. The Event Hubs receiver stores its
consumer checkpoints under `data/otel-collector-checkpoints`. Event Hubs
retention is finite, and the Terraform export rule does not backfill data from
before it became active.

VictoriaMetrics and VictoriaLogs each use seven-day retention and ephemeral
container storage. Their data is lost whenever their containers are removed
or recreated; retention does not protect data across container replacement.
Grafana also uses ephemeral storage: users, preferences, and UI-created dashboards
are lost on container removal or recreation. Its provisioned data sources are
recreated automatically.

## Prerequisites

- A deployed Azure environment with the AKS metrics identity, Event Hub, and
  Log Analytics export configured. The required Terraform outputs must be
  available from `../../terraform/otel-azure`.
- Docker with the Compose plugin.
- OpenTofu (`tofu`), Azure CLI (`az`), and OpenSSL.
- An Azure CLI login with access to the deployed subscription and AKS cluster.
- Network access to pull the Collector Contrib, VictoriaMetrics, VictoriaLogs,
  and Grafana images, and to download the VictoriaLogs plugin from Grafana's
  plugin catalog on each Grafana container recreation.

The service principal used by the Collector needs subscription-level resource
discovery permission and **Monitoring Reader** access to the AKS resource
group. Its Listen-only Event Hubs connection string is obtained from the
OpenTofu output. The Terraform state contains the generated client secret;
protect the state and do not commit the secret or `.env`.

## Prepare the local deployment

From this directory, create the ignored local environment file and development
certificates. If using a public endpoint for AKS testing, include
its hostname and/or IP address in the server certificate before generating
the certificates:

```bash
cp .env.example .env
umask 077
chmod 600 .env
OTEL_SERVER_DNS_NAMES="otel-collector,localhost,otel.example.net" \
OTEL_SERVER_IP_ADDRESSES="203.0.113.24" \
  sh scripts/generate-local-certs.sh
id -g
```

Replace the example endpoint values with the public DNS name/IP used by your
router rule.

`OTEL_SERVER_DNS_NAMES` and `OTEL_SERVER_IP_ADDRESSES` are comma-separated
lists; the existing local DNS names remain the default. The first DNS name is
also used as the server certificate's Common Name; every configured name and
IP address is included in its Subject Alternative Name extension. Use the
public DNS name or public IP that the AKS agent will connect to, not the Docker
host's private LAN address. The server certificate must include that exact
name/IP and the agent must trust the matching local CA. The generator refuses to overwrite existing certificates. If local
certificates already exist, rotate the CA and server certificate together,
update the AKS Secret with `../../terraform/otel-azure/scripts/otel-agent.sh`,
and restart the local Collector. The generated client certificate is not used by the Entra ID authentication
configuration. The default output directory is this project’s `certs/`
directory, even when the script is run from another working directory.

If upgrading from the previous API-key setup, remove any `OTEL_API_KEY` entry
from `.env`; the token is no longer used.

Set `CERT_GID` in `.env` to the numeric group ID printed by `id -g`. The
Collector runs as a non-root user and needs group read access to its
certificates. The generated certificates are for local development only; do
not use them in production.

The environment template already sets the Event Hubs consumer group to
`$Default` and the checkpoint storage directory to
`/var/lib/otelcol/storage-v2`. The start script refreshes the Azure tenant,
client credentials, subscription, resource group, Event Hubs connection string,
and consumer group from OpenTofu outputs. Ensure the deployment has the
`enable_azure_monitor_metrics = false` and `enable_otel_metrics_reader = true`
settings to disable the AKS-managed metrics add-on while retaining the external
Collector's Azure Monitor reader, and `enable_event_hub = true` for Event Hubs.

Grafana allows anonymous access with the Admin role; its login form and basic
authentication are disabled. This is intended only for local development. The
UI is bound to `127.0.0.1:3000`; keep it loopback-only because anyone who can
reach it has full Grafana administration access. The setup script removes the
obsolete `GRAFANA_ADMIN_USER` and `GRAFANA_ADMIN_PASSWORD` entries from `.env`;
no Grafana credentials are required.

## Start and stop with `otel.sh`

Start the entire stack from this directory:

```bash
./scripts/otel.sh --start
```

`--start` runs `scripts/setenv.sh` before starting the services. The setup script
reads the required OpenTofu outputs, signs in to Azure CLI if needed, selects
the deployment subscription, verifies the tenant, and updates the local AKS
kubeconfig. It refreshes the Azure values in `.env` from those outputs while
preserving other local settings and removing obsolete Grafana credentials,
then stops and removes the existing Compose project
containers and clears and recreates the Event Hubs checkpoint directory. The
script finally starts all four services: the Collector, VictoriaMetrics,
VictoriaLogs, and Grafana.

**Important:** every `--start` clears the saved Event Hubs checkpoints. A fresh
checkpoint store can skip messages already waiting in the Event Hub, so do not
use `--start` when you need to preserve the current consumer position. The
start operation also removes other containers in this Compose project,
including Grafana, VictoriaMetrics, and VictoriaLogs and their ephemeral
data. All services are then started again. Grafana's data sources are
provisioned again; UI-created state is not restored.

Follow Collector output with:

```bash
docker compose logs -f otel-collector
```

Stop all four services without removing their containers:

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
and the service definition is in [`compose.yaml`](compose.yaml). OTLP receivers
require an Entra ID access token over TLS. The OIDC authenticator validates the
token issuer against the deployment tenant and its audience against
`OTEL_OIDC_AUDIENCE`, populated from OpenTofu. AKS agents use a federated
user-assigned managed identity to obtain that token; the receiver app requires
an application-role assignment. The local client-certificate authentication
settings are commented out; keep TLS enabled to protect the connection. Set
`OTEL_GRPC_BIND_ADDRESS` in `.env` to the Docker host's LAN interface address
to accept traffic forwarded by your router on either OTLP port. Keep it at
`127.0.0.1` when remote access is not needed. The Collector uses the following
certificate files created by the local certificate script:

| File | Purpose |
| --- | --- |
| `certs/ca/ca.crt` | Trust anchor used by AKS agents to verify the Collector's TLS server certificate |
| `certs/server/server.crt` | Server certificate; its DNS/IP SANs include the local defaults and any configured public endpoint names |
| `certs/server/server.key` | Server private key |

The Azure values in `.env` are populated from the OpenTofu deployment by
`scripts/setenv.sh`. `CERT_GID` is a local setting and is preserved when that
script updates the file. The AKS deploy script reads the managed identity
client ID and OTLP scope from OpenTofu and stores only the CA certificate in
the namespace Secret. The external Collector continues using the service
principal credentials for its Azure Monitor receiver; it does not use a
managed identity because it runs outside Azure. Keep `.env`, private keys, and
Terraform state protected and out of source control.

VictoriaMetrics receives metric samples at
`http://victoria-metrics:8428/api/v1/write`; the Collector's Azure Monitor
metrics pipeline uses Prometheus remote write. VictoriaLogs receives OTLP logs
at `http://victoria-logs:9428/insert/opentelemetry/v1/logs`. Both backends are
available from the Docker host on loopback only:

| Backend | Local UI | API port |
| --- | --- | --- |
| VictoriaMetrics | `http://127.0.0.1:8428/vmui/` | `8428` |
| VictoriaLogs | `http://127.0.0.1:9428/select/vmui/` | `9428` |

### Grafana

Open `http://127.0.0.1:3000`; no login is required. Anonymous access is enabled,
with the Admin role for local development. The login form, basic
authentication, and user self-registration are disabled. Keep this UI bound to
loopback; Grafana runs OSS image `grafana/grafana:13.3.1`.

The read-only files in [`grafana/provisioning/datasources/`](grafana/provisioning/datasources/)
automatically create these data sources at startup:

| Data source | Type | Internal URL | Default |
| --- | --- | --- | --- |
| VictoriaMetrics | Built-in Prometheus | `http://victoria-metrics:8428` | Yes |
| VictoriaLogs | `victoriametrics-logs-datasource` | `http://victoria-logs:9428` | No |

These URLs use Compose service DNS, not host loopback; Grafana queries both
backends server-side. Data sources have stable UIDs (`victoria-metrics` and
`victoria-logs`) and cannot be edited in the UI. Change their YAML definitions
and restart Grafana to apply connection changes.

The VictoriaLogs plugin is pinned to `0.34.0` to retain compatibility with the
existing VictoriaLogs `v1.53.0`. It installs synchronously before data-source
provisioning. Plugin download failures are visible in Grafana's container logs;
outbound plugin-catalog access is needed on recreation because plugins are not
persisted. Recheck backend compatibility before upgrading the plugin.

In **Explore**, choose **VictoriaMetrics** and run a PromQL query such as
`count({__name__!=""})`, or choose **VictoriaLogs** and use LogsQL `*` to
search logs in the selected time range. No dashboards or alerts are provisioned.

Both the OTLP and Event Hubs logs pipelines export to VictoriaLogs over
OTLP/HTTP. Event Hubs records are decoded and parsed as JSON before export.

To inspect runtime state or diagnose startup problems, use:

```bash
docker compose ps
docker compose logs --tail=100 otel-collector
docker compose logs --tail=100 grafana
```

## Temporarily receive OTLP/HTTP from AKS

1. Set `OTEL_GRPC_BIND_ADDRESS` in `.env` to the Docker host's LAN address
   (for example, `192.168.1.20`), then validate and restart the Collector:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose --env-file .env up -d --force-recreate otel-collector
   docker compose --env-file .env port otel-collector 4318
   ```

2. Configure a temporary router TCP port-forward from external port `4318` to
   that Docker host LAN address and port `4318`. Restrict the router/firewall
   source allowlist to the dev AKS cluster's outbound public IP address(es);
   do not allow arbitrary Internet sources. The AKS API-server authorized IP
   range is not the same as the cluster's outbound source IP.
3. Configure the AKS agent's OTLP endpoint as
   `https://<public-DNS-name>:4318` (preferred) or the matching public IP URL.
   Ensure that exact DNS name or IP is present in `certs/server/server.crt`
   and that the agent uses `certs/ca/ca.crt` to verify it. The agent
   authenticates with an Entra ID access token acquired through AKS Workload
   Identity. The local certificate defaults do not contain a public endpoint
   SAN.
4. After the test, remove/disable the router NAT and firewall rule, then
   restore `OTEL_GRPC_BIND_ADDRESS=127.0.0.1` and re-create the service:

   ```bash
   docker compose --env-file .env up -d --force-recreate otel-collector
   ```

   TLS and Entra ID token validation remain enabled while the port is
   published.

Event Hubs log records are exported to VictoriaLogs over the internal Compose
network. Review access controls and configure durable storage before relying on
this test stack for long-term retention.
