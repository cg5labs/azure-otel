#!/usr/bin/env bash
#
# az-infra.sh - Provision or destroy the otel-azure OpenTofu infrastructure.
#
# Usage:
#   ./az-infra.sh (-up|--up|-down|--down) [-auto|--auto]
#
# Options:
#   -up, --up       Initialize, plan, and apply the deployment.
#   -down, --down   Destroy the deployment.
#   -auto, --auto   Skip OpenTofu approval prompts. Azure CLI login may still
#                   require interaction when no session is active.
#
# Requires Azure CLI, OpenTofu, and GNU getopt.
set -Eeuo pipefail

ACTION=""
AUTO_APPROVE=false
PROJECT_DIR=""
TFVARS_FILE=""
PLAN_FILE=""

# --- CLI and project setup ---

usage() {
  printf 'Usage: %s (-up|--up|-down|--down) [-auto|--auto]\n' "${0##*/}" >&2
}

parse_args() {
  local parsed_args

  # Alternative mode accepts -up as a single-dash long option.
  if ! parsed_args="$(getopt -a -o '' -l up,down,auto -- "$@")"; then
    usage
    exit 2
  fi

  eval set -- "$parsed_args"
  while true; do
    case "$1" in
      --up|--down)
        if [[ -n "$ACTION" ]]; then
          usage
          exit 2
        fi
        ACTION=${1#--}
        shift
        ;;
      --auto)
        if [[ "$AUTO_APPROVE" == true ]]; then
          usage
          exit 2
        fi
        AUTO_APPROVE=true
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        usage
        exit 2
        ;;
    esac
  done

  if [[ -n "$ACTION" && $# -eq 0 ]]; then
    return
  fi
  usage
  exit 2
}

require_commands() {
  local command_name
  local getopt_status=0

  for command_name in az tofu getopt; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      printf 'Required command not found: %s\n' "$command_name" >&2
      exit 1
    fi
  done

  getopt --test >/dev/null 2>&1 || getopt_status=$?
  if [[ $getopt_status -ne 4 ]]; then
    printf 'GNU getopt is required to parse the long options.\n' >&2
    exit 1
  fi
}

resolve_project_paths() {
  local script_dir

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_DIR="$(cd -- "$script_dir/.." && pwd)"
  TFVARS_FILE="$PROJECT_DIR/dev/terraform.tfvars"

  if [[ ! -f "$TFVARS_FILE" ]]; then
    printf 'Terraform variable file not found: %s\n' "$TFVARS_FILE" >&2
    exit 1
  fi
}

# --- Azure CLI authentication ---

authenticate_azure() {
  local subscription_id

  if ! az account show --output none >/dev/null 2>&1; then
    printf 'No active Azure CLI session. Starting az login...\n' >&2
    az login --output none
  fi

  subscription_id="$(
    awk -F '"' '/^[[:space:]]*subscription_id[[:space:]]*=/ { if ($2 != "") print $2; exit }' \
      "$TFVARS_FILE"
  )"
  if [[ -z "$subscription_id" ]]; then
    subscription_id="$(az account show --query id --output tsv)"
  fi
  if [[ -z "$subscription_id" ]]; then
    printf 'Unable to determine the Azure subscription ID.\n' >&2
    exit 1
  fi

  az account set --subscription "$subscription_id"
  az account get-access-token \
    --resource https://management.azure.com/ \
    --output none
  az account show --query '{name:name,id:id,tenantId:tenantId}' --output table
}

# --- OpenTofu actions ---

initialize_opentofu() {
  cd "$PROJECT_DIR"
  tofu init -input=false
}

confirm_apply() {
  local confirmation

  if [[ "$AUTO_APPROVE" == true ]]; then
    return
  fi
  if [[ ! -t 0 ]]; then
    printf 'A terminal is required to confirm applying the plan; use the auto option to approve it.\n' >&2
    exit 1
  fi

  read -r -p 'Apply this plan? [y/N] ' confirmation
  case "$confirmation" in
    y|Y|yes|YES) ;;
    *)
      printf 'Apply cancelled.\n' >&2
      exit 1
      ;;
  esac
}

cleanup_plan() {
  if [[ -n "$PLAN_FILE" ]]; then
    rm -f -- "$PLAN_FILE"
  fi
}

provision_infrastructure() {
  umask 077
  PLAN_FILE="$(mktemp "${TMPDIR:-/tmp}/otel-azure-plan.XXXXXX")"
  trap cleanup_plan EXIT

  tofu plan -input=false -var-file="$TFVARS_FILE" -out="$PLAN_FILE"
  confirm_apply
  tofu apply "$PLAN_FILE"
}

destroy_infrastructure() {
  if [[ "$AUTO_APPROVE" == true ]]; then
    tofu destroy -auto-approve -var-file="$TFVARS_FILE"
  else
    tofu destroy -var-file="$TFVARS_FILE"
  fi
}

# --- Main execution flow ---

main() {
  parse_args "$@"
  require_commands
  resolve_project_paths
  authenticate_azure
  initialize_opentofu

  case "$ACTION" in
    up) provision_infrastructure ;;
    down) destroy_infrastructure ;;
  esac
}

main "$@"
