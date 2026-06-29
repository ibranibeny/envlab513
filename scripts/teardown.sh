#!/usr/bin/env bash
# ===========================================================================
# LAB513 - teardown script
# Deletes everything deploy.sh created and purges the soft-deleted Azure AI
# (Cognitive Services) account so the name can be reused and you stop paying.
#
# Resolution order for what to delete:
#   1. --instance ID            (explicit)
#   2. lab513/.env              (written by deploy.sh)
#   3. --resource-group NAME    (explicit)
#
# DESTRUCTIVE. Requires typing 'yes' unless --yes is passed.
#
# Usage:
#   ./teardown.sh [--instance ID] [--resource-group NAME]
#                 [--subscription SUB] [--keep-fabric] [--yes]
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${ROOT_DIR}/.env"
GEN_DIR="${ROOT_DIR}/.generated"

LAB_INSTANCE_ID=""
RG=""
SUBSCRIPTION=""
KEEP_FABRIC=0
AUTO_YES=0

# ----- arg parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance)        LAB_INSTANCE_ID="$2"; shift 2;;
    --resource-group)  RG="$2"; shift 2;;
    --subscription)    SUBSCRIPTION="$2"; shift 2;;
    --keep-fabric)     KEEP_FABRIC=1; shift;;
    --yes|-y)          AUTO_YES=1; shift;;
    -h|--help)         grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "Unknown argument: $1 (use --help)";;
  esac
done
export AUTO_YES

# ----- load .env if present (for names + AI account to purge) --------------
# CLI args take precedence over .env, so remember what the user passed first.
CLI_INSTANCE="$LAB_INSTANCE_ID"
CLI_RG="$RG"
AI_FOUNDRY=""; AI_LOCATION=""; FABRIC_CAPACITY=""
if [[ -f "$ENV_FILE" ]]; then
  log "Reading ${ENV_FILE} ..."
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
# Re-apply CLI overrides (they win over anything sourced from .env).
[[ -n "$CLI_INSTANCE" ]] && LAB_INSTANCE_ID="$CLI_INSTANCE"
RG="${CLI_RG:-${RESOURCE_GROUP:-${RG:-}}}"

# Derive RG from instance id if still unknown.
if [[ -z "$RG" && -n "$LAB_INSTANCE_ID" ]]; then
  RG="rg-lab513-${LAB_INSTANCE_ID}"
fi
[[ -n "$RG" ]] || die "Cannot determine the resource group. Pass --instance ID or --resource-group NAME, or run from a folder containing .env."

# ----- preflight -----------------------------------------------------------
hr; log "LAB513 teardown - preflight"; hr
require_cmd az "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
require_cmd curl ""
preflight_network
ensure_login

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"; ensure_login
fi

if ! az group show -n "$RG" >/dev/null 2>&1; then
  warn "Resource group '${RG}' not found (already deleted?)."
else
  log "Resources to be deleted in '${RG}':"
  az resource list -g "$RG" --query "[].{name:name, type:type, location:location}" -o table 2>/dev/null || true
fi

# ----- confirm -------------------------------------------------------------
hr
printf '%sThis will DELETE resource group %s and ALL resources in it.%s\n' "$C_BOLD" "$RG" "$C_RESET"
[[ -n "$AI_FOUNDRY" ]] && printf 'It will also PURGE the soft-deleted AI account %s.\n' "$AI_FOUNDRY"
hr
confirm "Are you absolutely sure?" || die "Aborted by user."

# ----- delete Fabric capacity first (not in some RG views) -----------------
if [[ "$KEEP_FABRIC" == "0" && -n "${FABRIC_CAPACITY:-}" ]]; then
  if az fabric capacity show -g "$RG" -n "$FABRIC_CAPACITY" >/dev/null 2>&1; then
    log "Deleting Fabric capacity ${FABRIC_CAPACITY} ..."
    az fabric capacity delete -g "$RG" -n "$FABRIC_CAPACITY" --yes -o none 2>/dev/null \
      && ok "Fabric capacity deleted." \
      || warn "Could not delete Fabric capacity via CLI; remove it from the portal if it remains."
  fi
fi

# ----- delete the resource group ------------------------------------------
if az group show -n "$RG" >/dev/null 2>&1; then
  log "Deleting resource group ${RG} (this can take several minutes) ..."
  az group delete -n "$RG" --yes -o none
  ok "Resource group ${RG} deleted."
fi

# ----- purge soft-deleted AI (Cognitive Services) account ------------------
# AIServices/OpenAI accounts are soft-deleted: the name stays reserved and can
# still incur policy issues until purged. Purge it explicitly.
if [[ -n "$AI_FOUNDRY" && -n "$AI_LOCATION" ]]; then
  log "Purging soft-deleted AI account ${AI_FOUNDRY} in ${AI_LOCATION} ..."
  if az cognitiveservices account purge \
        --name "$AI_FOUNDRY" --resource-group "$RG" --location "$AI_LOCATION" -o none 2>/dev/null; then
    ok "AI account purged."
  else
    warn "Purge skipped/failed (it may already be gone). Check soft-deleted accounts with:"
    warn "  az cognitiveservices account list-deleted -o table"
  fi
fi

# ----- clean up local generated artifacts ----------------------------------
if [[ -d "$GEN_DIR" ]]; then
  rm -rf "$GEN_DIR"; ok "Removed ${GEN_DIR}."
fi
if [[ -f "$ENV_FILE" ]]; then
  if confirm "Delete local ${ENV_FILE} (contains the SQL password)?"; then
    rm -f "$ENV_FILE"; ok "Removed ${ENV_FILE}."
  else
    warn "Kept ${ENV_FILE} - delete it manually when done."
  fi
fi

hr; ok "LAB513 teardown complete."; hr
cat <<EOF
  If you created any of these manually in the portal, remove them too:
    - Microsoft Foundry project 'FAQ-Assistant-project' and the MCP tool/agent
    - Microsoft Fabric workspace 'Workspace${LAB_INSTANCE_ID:-<id>}' (+ mirrored db, semantic model, report)
    - Any running devtunnel:  devtunnel delete my-faq-tunnel${LAB_INSTANCE_ID:-<id>}
EOF
