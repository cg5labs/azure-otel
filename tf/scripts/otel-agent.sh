#!/usr/bin/env bash
#
# Deploy or upgrade the node-local OpenTelemetry Collector on AKS.
#
# Required environment:
#   OTEL_AGENT_OTLP_ENDPOINT       External OTLP/HTTP URL (https://host:4318)
#   OTEL_AGENT_CA_FILE             CA certificate trusted by the external Collector
#
# Requires Azure CLI, OpenTofu, Helm, kubectl, kubelogin, and sha256sum.
set -Eeuo pipefail
umask 077

readonly HELM_REPOSITORY="https://open-telemetry.github.io/opentelemetry-helm-charts"
readonly HELM_CHART_VERSION="0.178.3"
readonly HELM_CHART_NAME="opentelemetry-collector"
readonly HELM_RELEASE_NAME="otel-agent"
readonly KUBERNETES_NAMESPACE="otel-agent"
readonly KUBERNETES_SECRET_NAME="otel-agent-mtls"

PROJECT_DIR=""
VALUES_FILE=""
KUBECONFIG_DIR=""
KUBECONFIG_FILE=""

usage() {
  cat <<'EOF'
Usage: OTEL_AGENT_OTLP_ENDPOINT=https://host:4318 \
  OTEL_AGENT_CA_FILE=/path/to/ca.crt \
  ./scripts/otel-agent.sh

Deploys or upgrades the OpenTelemetry Collector DaemonSet on the AKS cluster
described by the OpenTofu state in this directory. Uses AKS Workload Identity
to authenticate OTLP exports to the external Collector.
EOF
}

require_commands() {
  local command_name

  for command_name in az tofu helm kubectl kubelogin sha256sum; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      printf 'Required command not found: %s\n' "$command_name" >&2
      exit 1
    fi
  done
}

require_file() {
  local variable_name="$1"
  local file_path="$2"

  if [[ -z "$file_path" || ! -f "$file_path" || ! -r "$file_path" ]]; then
    printf '%s must point to a readable certificate file.\n' "$variable_name" >&2
    exit 1
  fi
}

require_configuration() {
  if [[ -z "${OTEL_AGENT_OTLP_ENDPOINT:-}" ]]; then
    printf 'Set OTEL_AGENT_OTLP_ENDPOINT to the external OTLP/HTTP URL (https://host:4318).\n' >&2
    exit 1
  fi
  if [[ ! "$OTEL_AGENT_OTLP_ENDPOINT" =~ ^https://[^/[:space:]]+:[0-9]+$ ]]; then
    printf 'OTEL_AGENT_OTLP_ENDPOINT must be an HTTPS URL with a host and port, without a path.\n' >&2
    exit 1
  fi
  require_file OTEL_AGENT_CA_FILE "${OTEL_AGENT_CA_FILE:-}"
}

resolve_project_paths() {
  local script_dir

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_DIR="$(cd -- "$script_dir/.." && pwd)"
  VALUES_FILE="$PROJECT_DIR/helm/otel-collector-agent-values.yaml"

  if [[ ! -f "$VALUES_FILE" ]]; then
    printf 'Helm values file not found: %s\n' "$VALUES_FILE" >&2
    exit 1
  fi
}

tofu_output() {
  local output_name="$1"
  local output_value

  output_value="$(tofu -chdir="$PROJECT_DIR" output -raw "$output_name")"
  if [[ -z "$output_value" || "$output_value" == "null" ]]; then
    printf 'OpenTofu output is empty or null: %s\n' "$output_name" >&2
    exit 1
  fi
  printf '%s' "$output_value"
}

authenticate_azure() {
  if ! az account show --output none >/dev/null 2>&1; then
    printf 'No active Azure CLI session. Starting az login...\n' >&2
    az login --output none
  fi
}

cleanup() {
  if [[ -n "$KUBECONFIG_DIR" ]]; then
    rm -f -- "$KUBECONFIG_FILE"
    rmdir -- "$KUBECONFIG_DIR"
  fi
}

main() {
  local subscription_id resource_group_name cluster_name
  local identity_client_id otlp_scope auth_revision

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    return
  fi
  if [[ $# -ne 0 ]]; then
    usage >&2
    exit 2
  fi

  require_commands
  resolve_project_paths
  require_configuration

  tofu -chdir="$PROJECT_DIR" init -input=false
  subscription_id="$(tofu_output subscription_id)"
  resource_group_name="$(tofu_output resource_group_name)"
  cluster_name="$(tofu_output kubernetes_cluster_name)"
  identity_client_id="$(tofu_output otel_agent_managed_identity_client_id)"
  otlp_scope="$(tofu_output otel_otlp_scope)"

  authenticate_azure
  az account set --subscription "$subscription_id"

  KUBECONFIG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/otel-agent-kubeconfig.XXXXXX")"
  KUBECONFIG_FILE="$KUBECONFIG_DIR/config"
  trap cleanup EXIT
  az aks get-credentials \
    --subscription "$subscription_id" \
    --resource-group "$resource_group_name" \
    --name "$cluster_name" \
    --file "$KUBECONFIG_FILE" \
    --overwrite-existing

  auth_revision="$(
    {
      sha256sum -- "$OTEL_AGENT_CA_FILE"
      printf '%s\n%s' "$identity_client_id" "$otlp_scope" | sha256sum
    } |
      sha256sum
  )"
  auth_revision="${auth_revision%% *}"

  kubectl --kubeconfig "$KUBECONFIG_FILE" create namespace "$KUBERNETES_NAMESPACE" \
    --dry-run=client \
    --output=yaml |
    kubectl --kubeconfig "$KUBECONFIG_FILE" apply --filename=-

  kubectl --kubeconfig "$KUBECONFIG_FILE" \
    --namespace "$KUBERNETES_NAMESPACE" \
    create secret generic "$KUBERNETES_SECRET_NAME" \
    --from-file="ca.crt=$OTEL_AGENT_CA_FILE" \
    --dry-run=client \
    --output=yaml |
    kubectl --kubeconfig "$KUBECONFIG_FILE" \
      apply \
      --server-side \
      --force-conflicts \
      --field-manager=otel-agent \
      --filename=-

  helm upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART_NAME" \
    --repo "$HELM_REPOSITORY" \
    --version "$HELM_CHART_VERSION" \
    --namespace "$KUBERNETES_NAMESPACE" \
    --create-namespace \
    --kubeconfig "$KUBECONFIG_FILE" \
    --values "$VALUES_FILE" \
    --set-string "extraEnvs[0].value=$OTEL_AGENT_OTLP_ENDPOINT" \
    --set-string "extraEnvs[1].value=$otlp_scope" \
    --set-string "serviceAccount.annotations.azure\\.workload\\.identity/client-id=$identity_client_id" \
    --set-string "podAnnotations.otel-agent-auth-revision=$auth_revision" \
    --debug
    #--atomic \
    #--wait \
    #--timeout 5m

  kubectl --kubeconfig "$KUBECONFIG_FILE" \
    --namespace "$KUBERNETES_NAMESPACE" \
    rollout status "daemonset/$HELM_RELEASE_NAME" \
    --timeout=5m
}

main "$@"
