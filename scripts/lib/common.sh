#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# common.sh - shared helpers for LAB513 deploy / teardown scripts
# Sourced by deploy.sh and teardown.sh. Not meant to be run directly.
# ---------------------------------------------------------------------------

# ----- pretty logging ------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[34m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""
fi

log()  { printf '%s[ %s ]%s %s\n' "$C_BLUE"  "info" "$C_RESET" "$*"; }
ok()   { printf '%s[  ok ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[warn ]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[error]%s %s\n' "$C_RED"   "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
hr()   { printf '%s\n' "------------------------------------------------------------"; }

# ----- prerequisite checks -------------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH. $2"
}

# Verify outbound connectivity to Azure control plane.
# WSL distros frequently lose DNS/route while the Windows host stays online,
# so we check explicitly and fail with an actionable message.
preflight_network() {
  log "Checking outbound connectivity to Azure (management.azure.com) ..."
  if curl -fsS -m 8 -o /dev/null "https://management.azure.com/"; then
    ok "Azure control plane reachable."
    return 0
  fi
  err "Cannot reach https://management.azure.com from this shell."
  cat >&2 <<'EOF'

  This is almost always a WSL networking issue (the Windows host can be online
  while the WSL distro cannot resolve/route to Azure). Try ONE of:

    1) Fix WSL DNS:
         echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
       (or enable mirrored networking in %UserProfile%\.wslconfig:
         [wsl2]
         networkingMode=mirrored
        then run:  wsl --shutdown   from PowerShell and reopen WSL)

    2) Run this script from Windows PowerShell with Azure CLI installed.

    3) Run it from Azure Cloud Shell (https://shell.azure.com) which always
       has connectivity and the CLI pre-installed.

EOF
  die "Network preflight failed."
}

ensure_login() {
  log "Checking Azure CLI sign-in ..."
  if ! az account show >/dev/null 2>&1; then
    die "Not signed in. Run:  az login   (or  az login --use-device-code )"
  fi
  CURRENT_SUB_NAME=$(az account show --query name -o tsv)
  CURRENT_SUB_ID=$(az account show --query id -o tsv)
  CURRENT_USER=$(az account show --query user.name -o tsv)
  ok "Signed in as ${CURRENT_USER} on subscription '${CURRENT_SUB_NAME}'."
}

# ----- region / capability validation -------------------------------------
# All validators are best-effort: on a query failure they WARN and return 0 so
# the actual 'az ... create' call remains the final source of truth. They never
# silently mask a definite "not available" answer.

region_display_name() {
  az account list-locations --query "[?name=='$1'].displayName | [0]" -o tsv 2>/dev/null
}

validate_sql_hyperscale() {
  local loc="$1" count
  count=$(az sql db list-editions -l "$loc" --edition Hyperscale \
            --query "length([?name=='Hyperscale'])" -o tsv 2>/dev/null || echo "")
  if [[ -z "$count" ]]; then
    warn "Could not query SQL editions in '$loc' (continuing; create will enforce)."
    return 0
  fi
  [[ "$count" -ge 1 ]]
}

# Returns 0 if BOTH the chat and embedding models are deployable in the region.
ai_region_has_models() {
  local loc="$1" chat="$2" emb="$3" models
  models=$(az cognitiveservices model list -l "$loc" --query "[].model.name" -o tsv 2>/dev/null || echo "")
  if [[ -z "$models" ]]; then
    warn "Could not list Foundry/OpenAI models in '$loc'."
    return 1
  fi
  grep -qx "$chat" <<<"$models" && grep -qx "$emb" <<<"$models"
}

# Pick the first AI region (from a preference list) that has both models.
pick_ai_location() {
  local chat="$1" emb="$2"; shift 2
  local candidates=("$@") loc
  for loc in "${candidates[@]}"; do
    log "Probing AI region '$loc' for ${chat} + ${emb} ..." >&2
    if ai_region_has_models "$loc" "$chat" "$emb"; then
      ok "AI region '$loc' has both models." >&2
      printf '%s' "$loc"; return 0
    fi
  done
  # Fall back to the first candidate; create will report the real error.
  warn "No probed AI region confirmed both models; defaulting to '${candidates[0]}'." >&2
  printf '%s' "${candidates[0]}"
}

validate_fabric_region() {
  local loc_display="$1" locs
  locs=$(az provider show --namespace Microsoft.Fabric \
          --query "resourceTypes[?resourceType=='capacities'].locations | [0]" -o tsv 2>/dev/null || echo "")
  if [[ -z "$locs" ]]; then
    warn "Could not query Microsoft.Fabric locations (continuing)."
    return 0
  fi
  grep -qi -- "$loc_display" <<<"$locs"
}

# ----- misc helpers --------------------------------------------------------
gen_password() {
  # 24-char password guaranteed to satisfy Azure SQL complexity rules.
  local base
  base=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
  printf 'Aa1!%s' "$base"
}

confirm() {
  # confirm "<prompt>"  -> returns 0 if user types yes (or AUTO_YES=1)
  local prompt="$1" reply
  if [[ "${AUTO_YES:-0}" == "1" ]]; then return 0; fi
  read -r -p "$prompt [type 'yes' to continue]: " reply
  [[ "$reply" == "yes" ]]
}
