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

# ----- phase timing --------------------------------------------------------
# phase "5/6  Microsoft Fabric"  prints the section header AND closes timing on
# the previous phase. print_timing_summary() flushes the final phase and a
# duration table so every run reports how long each step took.
_PHASE_NAMES=(); _PHASE_SECS=(); _CUR_PHASE=""; _CUR_T0=0
fmt_secs() { local s="${1:-0}"; printf '%dm%02ds' $(( s / 60 )) $(( s % 60 )); }
_close_phase() {
  [[ -z "$_CUR_PHASE" ]] && return 0
  _PHASE_NAMES+=("$_CUR_PHASE"); _PHASE_SECS+=( $(( $(date +%s) - _CUR_T0 )) ); _CUR_PHASE=""
}
phase() { _close_phase; _CUR_PHASE="$*"; _CUR_T0=$(date +%s); hr; log "$*"; hr; }
print_timing_summary() {
  _close_phase
  local i total=0
  hr; printf '%s[ time ]%s phase durations\n' "$C_BLUE" "$C_RESET"
  for i in "${!_PHASE_NAMES[@]}"; do
    printf '   %-46s %s\n' "${_PHASE_NAMES[$i]}" "$(fmt_secs "${_PHASE_SECS[$i]}")"
    total=$(( total + ${_PHASE_SECS[$i]} ))
  done
  printf '   %-46s %s\n' "TOTAL" "$(fmt_secs "$total")"; hr
}

# ----- az interop CRLF guard -----------------------------------------------
# In WSL the Azure CLI is often the Windows az.exe reached via /mnt/c interop
# (native Linux az can be blocked by GSA). az.exe emits CRLF line endings, and
# the trailing \r corrupts bash string comparisons and arithmetic (e.g.
# "invalid arithmetic operator (error token is ...)"). Wrap az so every call
# strips CR from its output. `set -o pipefail` (set by the callers) preserves
# az's real exit status through the pipe.
if command -v az >/dev/null 2>&1; then
  _AZ_BIN="$(command -v az)"
  case "$_AZ_BIN" in
    /mnt/*|*.exe)
      az() { "$_AZ_BIN" "$@" | tr -d '\r'; }
      ;;
  esac
fi

# ----- prerequisite checks -------------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH. $2"
}

# Verify outbound connectivity to Azure control plane.
# WSL distros frequently lose DNS/route while the Windows host stays online,
# so we check explicitly and fail with an actionable message.
preflight_network() {
  log "Checking outbound connectivity to Azure (management.azure.com) ..."
  # A bare, unauthenticated GET to ARM returns HTTP 400/401 - that still proves
  # the endpoint is REACHABLE. Treat "got any HTTP status" as success; only a
  # real connection/DNS failure (curl code 000) means there is no route.
  local code
  code="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' "https://management.azure.com/" 2>/dev/null || echo 000)"
  if [[ "$code" != "000" ]]; then
    ok "Azure control plane reachable (HTTP ${code})."
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

# Returns 0 if BOTH the chat and embedding models are deployable in the region
# at the requested versions WITH the GlobalStandard SKU (honest, SKU-aware probe).
ai_region_has_models() {
  local loc="$1" chat="$2" emb="$3" chat_ver="$4" emb_ver="$5" chat_ok emb_ok
  chat_ok=$(az cognitiveservices model list -l "$loc" \
    --query "length([?model.name=='${chat}' && model.version=='${chat_ver}' && contains(model.skus[].name,'GlobalStandard')])" \
    -o tsv 2>/dev/null || echo 0)
  emb_ok=$(az cognitiveservices model list -l "$loc" \
    --query "length([?model.name=='${emb}' && model.version=='${emb_ver}' && contains(model.skus[].name,'GlobalStandard')])" \
    -o tsv 2>/dev/null || echo 0)
  [[ "${chat_ok:-0}" -ge 1 && "${emb_ok:-0}" -ge 1 ]]
}

# Pick the first AI region (from a preference list) that supports both models
# at the requested versions with the GlobalStandard SKU.
pick_ai_location() {
  local chat="$1" emb="$2" chat_ver="$3" emb_ver="$4"; shift 4
  local candidates=("$@") loc
  for loc in "${candidates[@]}"; do
    log "Probing AI region '$loc' for ${chat} (${chat_ver}) + ${emb} (${emb_ver}) [GlobalStandard] ..." >&2
    if ai_region_has_models "$loc" "$chat" "$emb" "$chat_ver" "$emb_ver"; then
      ok "AI region '$loc' supports both models (GlobalStandard)." >&2
      printf '%s' "$loc"; return 0
    fi
  done
  # Fall back to the first candidate; create will report the real error.
  warn "No probed AI region confirmed both models (GlobalStandard); defaulting to '${candidates[0]}'." >&2
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

# ----- SQL connectivity + VM-delegated bootstrap ---------------------------
# Many corporate/ISP networks (incl. WSL behind Global Secure Access) drop
# outbound TCP 1433, so sqlcmd from the deploy host cannot reach Azure SQL even
# though the SQL firewall is wide open. An Azure VM reaches 1433 over the Azure
# backbone, so we detect the block and delegate the bootstrap to a VM.

# Returns 0 if TCP <host>:<port> is reachable from this shell within ~6s.
tcp_port_open() {
  local host="$1" port="${2:-1433}"
  timeout 6 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null
}

# Echo "<resourceGroup>\t<name>" of a running Windows VM that can run the SQL
# bootstrap from inside Azure. Prefers VMs whose name contains 'lab513'.
detect_bootstrap_vm() {
  local out
  out=$(az vm list -d \
    --query "[?powerState=='VM running' && storageProfile.osDisk.osType=='Windows' && contains(name,'lab513')].[resourceGroup,name] | [0]" \
    -o tsv 2>/dev/null)
  if [[ -z "$out" ]]; then
    out=$(az vm list -d \
      --query "[?powerState=='VM running' && storageProfile.osDisk.osType=='Windows'].[resourceGroup,name] | [0]" \
      -o tsv 2>/dev/null)
  fi
  printf '%s' "$out"
}

# run_sql_files_via_vm <vm_rg> <vm_name> <sql_server> <sql_db> <sql_admin> <sql_pwd> -- <file> [<file> ...]
# Builds a PowerShell script that runs each SQL file (split on GO) against Azure
# SQL via .NET SqlClient, then executes it on the VM with az vm run-command.
# Server-side calls (sp_invoke_external_rest_endpoint -> Azure OpenAI) still use
# the SQL managed identity, so delegating only moves WHO submits the batch.
run_sql_files_via_vm() {
  local vm_rg="$1" vm_name="$2" sql_server="$3" sql_db="$4" sql_admin="$5" sql_password="$6"
  shift 6
  local files=("$@") f ps msg
  ps="$(mktemp /tmp/lab513-vm-bootstrap.XXXXXX.ps1)"
  {
    printf '%s\n' "\$ErrorActionPreference='Stop'"
    printf '%s\n' "\$cs = 'Server=tcp:${sql_server}.database.windows.net,1433;Database=${sql_db};User ID=${sql_admin};Password=${sql_password};Encrypt=True;TrustServerCertificate=False;Connection Timeout=60'"
    cat <<'PSFUNC'
function Invoke-SqlB64([string]$b64,[string]$name){
  Write-Output "=== $name ==="
  $sql=[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
  $cn=New-Object System.Data.SqlClient.SqlConnection $cs
  $cn.Open()
  try {
    foreach($b in ($sql -split "(?im)^\s*GO\s*$")){
      if($b.Trim()){ $c=$cn.CreateCommand(); $c.CommandText=$b; $c.CommandTimeout=600; [void]$c.ExecuteNonQuery() }
    }
  } finally { $cn.Close() }
}
PSFUNC
    for f in "${files[@]}"; do
      printf 'Invoke-SqlB64 -b64 "%s" -name "%s"\n' "$(base64 -w0 "$f")" "$(basename "$f")"
    done
    cat <<'PSTAIL'
$cn=New-Object System.Data.SqlClient.SqlConnection $cs
$cn.Open()
$c=$cn.CreateCommand()
$c.CommandText="SELECT (SELECT COUNT(*) FROM dbo.FAQ_Content) AS faq, (SELECT COUNT(*) FROM dbo.FAQ_Embeddings WHERE question_embedding IS NOT NULL) AS emb"
$r=$c.ExecuteReader(); while($r.Read()){ Write-Output ("ROWS FAQ_Content=" + $r['faq'] + " Embeddings=" + $r['emb']) }
$cn.Close()
Write-Output "VM-BOOTSTRAP-DONE"
PSTAIL
  } > "$ps"

  msg=$(az vm run-command invoke -g "$vm_rg" -n "$vm_name" \
        --command-id RunPowerShellScript --scripts @"$ps" \
        --query "value[0].message" -o tsv 2>&1)
  rm -f "$ps"
  printf '%s\n' "$msg"
  grep -q "VM-BOOTSTRAP-DONE" <<<"$msg"
}
