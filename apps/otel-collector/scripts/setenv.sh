#!/usr/bin/env bash
set -Eeuo pipefail

# Resolve project paths relative to this script so it works from any directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AZURE_OTEL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOFU_DIR="$(cd -- "$AZURE_OTEL_DIR/../../tf" && pwd)"
ENV_FILE="$AZURE_OTEL_DIR/.env"
CHECKPOINT_DIR="$AZURE_OTEL_DIR/data/otel-collector-checkpoints"
TEMP_ENV_FILE=""
AKS_CLUSTER_NAME=""

# These are populated from OpenTofu and updated in the local Collector .env.
UPDATE_KEYS=(
  AZURE_TENANT_ID
  AZURE_CLIENT_ID
  AZURE_CLIENT_SECRET
  AZURE_SUBSCRIPTION_ID
  AZURE_RESOURCE_GROUP
  AZURE_EVENTHUB_CONNECTION_STRING
  AZURE_EVENTHUB_CONSUMER_GROUP
)
declare -A ENV_VALUES=()
declare -A WRITTEN_KEYS=()

# Remove an incomplete temporary file if any step fails.
cleanup_temp_env() {
  if [[ -n "$TEMP_ENV_FILE" ]]; then
    printf 'Removing incomplete temporary environment file.\n' >&2
    rm -f -- "$TEMP_ENV_FILE"
  fi
}

# Read a single output without printing its value, including sensitive outputs.
read_tofu_output() {
  local output_name="$1"
  local value

  printf 'Reading OpenTofu output: %s\n' "$output_name" >&2
  if ! value="$(tofu -chdir="$TOFU_DIR" output -raw "$output_name")"; then
    printf 'Unable to read OpenTofu output "%s". Apply the otel-azure project and ensure the related feature is enabled.\n' \
      "$output_name" >&2
    return 1
  fi
  if [[ -z "$value" || "$value" == "null" ]]; then
    printf 'OpenTofu output "%s" is empty; refusing to continue.\n' "$output_name" >&2
    return 1
  fi
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    printf 'OpenTofu output "%s" contains a newline; refusing to continue.\n' "$output_name" >&2
    return 1
  fi

  printf '%s' "$value"
}

# Quote values as literals in the Docker Compose .env file.
quote_env_value() {
  local value="$1"

  value=${value//\\/\\\\}
  value=${value//\'/\\\'}
  printf "'%s'" "$value"
}

# Load only the values needed by the Azure Monitor and Event Hubs receivers.
read_tofu_outputs() {
  printf 'Loading Azure and Event Hubs settings from OpenTofu.\n'
  ENV_VALUES[AZURE_TENANT_ID]="$(read_tofu_output otel_service_principal_tenant_id)"
  ENV_VALUES[AZURE_CLIENT_ID]="$(read_tofu_output otel_service_principal_client_id)"
  ENV_VALUES[AZURE_CLIENT_SECRET]="$(read_tofu_output otel_service_principal_client_secret)"
  ENV_VALUES[AZURE_SUBSCRIPTION_ID]="$(read_tofu_output subscription_id)"
  ENV_VALUES[AZURE_RESOURCE_GROUP]="$(read_tofu_output resource_group_name)"
  ENV_VALUES[AZURE_EVENTHUB_CONNECTION_STRING]="$(read_tofu_output eventhub_sas_connection_string)"
  ENV_VALUES[AZURE_EVENTHUB_CONSUMER_GROUP]="$(read_tofu_output eventhub_consumer_group)"
  AKS_CLUSTER_NAME="$(read_tofu_output kubernetes_cluster_name)"
}

# Authenticate Azure CLI if needed and select the Terraform deployment's subscription.
authenticate_azure() {
  local active_tenant

  printf 'Checking Azure CLI login status.\n'
  if ! az account show --output none >/dev/null 2>&1; then
    printf 'No active Azure CLI session; signing in to the Terraform tenant.\n'
    az login --tenant "${ENV_VALUES[AZURE_TENANT_ID]}" --output none
  else
    printf 'Using the existing Azure CLI session.\n'
  fi

  printf 'Selecting Azure subscription %s.\n' "${ENV_VALUES[AZURE_SUBSCRIPTION_ID]}"
  az account set --subscription "${ENV_VALUES[AZURE_SUBSCRIPTION_ID]}"
  active_tenant="$(az account show --query tenantId --output tsv)"
  if [[ "$active_tenant" != "${ENV_VALUES[AZURE_TENANT_ID]}" ]]; then
    printf 'The active Azure CLI tenant does not match the Terraform tenant. Run az login --tenant %s and retry.\n' \
      "${ENV_VALUES[AZURE_TENANT_ID]}" >&2
    return 1
  fi

  printf 'Verifying Azure Resource Manager access.\n'
  az account get-access-token \
    --resource https://management.azure.com/ \
    --output none
}

# Merge AKS credentials into the user's default kubeconfig and select its context.
set_aks_kubeconfig() {
  printf 'Updating kubeconfig for AKS cluster %s in resource group %s.\n' \
    "$AKS_CLUSTER_NAME" "${ENV_VALUES[AZURE_RESOURCE_GROUP]}"
  az aks get-credentials \
    --subscription "${ENV_VALUES[AZURE_SUBSCRIPTION_ID]}" \
    --resource-group "${ENV_VALUES[AZURE_RESOURCE_GROUP]}" \
    --name "$AKS_CLUSTER_NAME" \
    --overwrite-existing
  printf 'AKS credentials are configured in the default kubeconfig.\n'
}

# Stop this Compose project and reset its Event Hub receiver checkpoints.
stop_compose_and_reset_checkpoints() {
  printf 'Stopping and removing all containers in the Azure OTEL Compose project.\n'
  docker compose \
    --project-directory "$AZURE_OTEL_DIR" \
    -f "$AZURE_OTEL_DIR/compose.yaml" \
    down --remove-orphans
  printf 'Compose containers are stopped.\n'

  if [[ -L "$CHECKPOINT_DIR" ]]; then
    printf 'Refusing to remove checkpoint path because it is a symbolic link: %s\n' \
      "$CHECKPOINT_DIR" >&2
    return 1
  fi

  printf 'Removing Event Hub checkpoint data at %s.\n' "$CHECKPOINT_DIR"
  rm -rf -- "$CHECKPOINT_DIR"
  mkdir -p -- "$CHECKPOINT_DIR"
  chmod 0775 "$CHECKPOINT_DIR"
  printf 'Checkpoint data cleared; recreated the empty bind-mount directory.\n'
}

# Atomically update Azure-specific .env keys and retain unrelated local settings.
write_env_file() {
  local line key

  printf 'Updating %s and preserving other local settings.\n' "$ENV_FILE"
  umask 077
  TEMP_ENV_FILE="$(mktemp "$AZURE_OTEL_DIR/.env.XXXXXX")"
  trap cleanup_temp_env EXIT

  while IFS= read -r line || [[ -n "$line" ]]; do
    key="${line%%=*}"
    if [[ "$line" == *=* && -n "${ENV_VALUES[$key]+set}" ]]; then
      if [[ -z "${WRITTEN_KEYS[$key]+set}" ]]; then
        printf '%s=%s\n' "$key" "$(quote_env_value "${ENV_VALUES[$key]}")" \
          >> "$TEMP_ENV_FILE"
        WRITTEN_KEYS["$key"]=1
      fi
      continue
    fi
    printf '%s\n' "$line" >> "$TEMP_ENV_FILE"
  done < "$ENV_FILE"

  for key in "${UPDATE_KEYS[@]}"; do
    if [[ -z "${WRITTEN_KEYS[$key]+set}" ]]; then
      printf '%s=%s\n' "$key" "$(quote_env_value "${ENV_VALUES[$key]}")" \
        >> "$TEMP_ENV_FILE"
    fi
  done

  chmod 600 "$TEMP_ENV_FILE"
  mv -- "$TEMP_ENV_FILE" "$ENV_FILE"
  TEMP_ENV_FILE=""
  printf 'Updated .env with OpenTofu outputs; secret values were not displayed.\n'
}

# Validate prerequisites, load outputs, configure Azure access, then update .env.
main() {
  local command_name

  printf 'Checking required commands and the local .env file.\n'
  for command_name in tofu az docker; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      printf 'Required command not found: %s\n' "$command_name" >&2
      return 1
    fi
  done
  if ! docker compose version >/dev/null 2>&1; then
    printf 'Docker Compose is required to stop the Azure OTEL services.\n' >&2
    return 1
  fi

  if [[ ! -f "$ENV_FILE" || -L "$ENV_FILE" ]]; then
    printf 'Expected a regular .env file at %s; create it from .env.example first.\n' \
      "$ENV_FILE" >&2
    return 1
  fi

  read_tofu_outputs
  authenticate_azure
  set_aks_kubeconfig
  stop_compose_and_reset_checkpoints
  write_env_file
}

main "$@"
