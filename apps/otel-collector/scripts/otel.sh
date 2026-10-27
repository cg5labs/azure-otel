#!/usr/bin/env bash
#
# otel.sh - Start or stop the OTEL Collector Compose service.
#
# Usage:
#   ./otel.sh --start
#   ./otel.sh --stop
#
# --start runs setenv.sh to refresh Azure settings and kubeconfig, bring down
# the Compose project, and clear Event Hub checkpoints. It then sources .env
# and starts the otel-collector service. Checkpoint reset can prevent replay
# of messages pending in Event Hubs before startup.
# --stop stops the otel-collector service without removing its container.
#
# Requires Docker Compose; --start also requires the tools used by setenv.sh.
set -Eeuo pipefail

# Resolve the Compose project and helper paths independently of the caller's cwd.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AZURE_OTEL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$AZURE_OTEL_DIR/compose.yaml"
ENV_FILE="$AZURE_OTEL_DIR/.env"
SETENV_SCRIPT="$SCRIPT_DIR/setenv.sh"

usage() {
  printf 'Usage: %s --start|--stop\n' "${0##*/}" >&2
}

require_compose() {
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    printf 'Docker with the Compose plugin is required.\n' >&2
    exit 1
  fi
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    printf 'Compose file not found: %s\n' "$COMPOSE_FILE" >&2
    exit 1
  fi
}

start_stack() {
  if [[ ! -x "$SETENV_SCRIPT" ]]; then
    printf 'Environment setup script is missing or not executable: %s\n' \
      "$SETENV_SCRIPT" >&2
    return 1
  fi

  printf 'Refreshing Azure environment settings and AKS kubeconfig.\n'
  "$SETENV_SCRIPT"

  if [[ ! -f "$ENV_FILE" ]]; then
    printf 'Environment file not found after setup: %s\n' "$ENV_FILE" >&2
    return 1
  fi

  printf 'Sourcing environment configuration from %s.\n' "$ENV_FILE"
  set -a
  # The local .env is sourced so Compose and any interpolated settings use the same values.
  source "$ENV_FILE"
  set +a

  printf 'Starting the OTEL Collector service.\n'
  docker compose \
    --project-directory "$AZURE_OTEL_DIR" \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    up -d --remove-orphans otel-collector
  printf 'OTEL Collector service is started.\n'
}

stop_stack() {
  if [[ ! -f "$ENV_FILE" ]]; then
    printf 'Environment file not found: %s\n' "$ENV_FILE" >&2
    return 1
  fi

  printf 'Stopping the OTEL Collector service.\n'
  docker compose \
    --project-directory "$AZURE_OTEL_DIR" \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    stop otel-collector
  printf 'OTEL Collector service is stopped.\n'
}

main() {
  if [[ $# -ne 1 ]]; then
    usage
    exit 2
  fi

  require_compose
  case "$1" in
    --start) start_stack ;;
    --stop) stop_stack ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
