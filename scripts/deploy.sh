#!/usr/bin/env bash
# ===========================================================================
# LAB513 - Build an AI app with Azure SQL Hyperscale, Microsoft Fabric & Foundry
# Deployment script (Azure CLI)
#
#   Primary region : Indonesia Central (indonesiacentral)
#   AI fallback     : Southeast Asia    (southeastasia)  <- Azure OpenAI is NOT
#                     available in Indonesia Central (verified on Microsoft Learn).
#
# Provisions, end to end:
#   - Resource group                         (indonesiacentral)
#   - VNet + Subnet + NSG (ALL in/out OPEN)  (indonesiacentral)   << lab only
#   - Azure SQL logical server + Hyperscale db (indonesiacentral)
#   - Azure AI Foundry (AIServices) + gpt-5 + text-embedding-3-small (southeastasia)
#     + Foundry project FAQ-Assistant-project (pre-provisioned for Exercise 4)
#   - Microsoft Fabric capacity (F2)         (indonesiacentral, optional)
#   - SQL bootstrap: tables, FAQ seed, embeddings, dbo.SearchFAQ (optional)
#
# SECURITY: the NSG and SQL firewall are intentionally wide open for a short-
# lived lab. This is INSECURE. Run ./teardown.sh as soon as you are done.
#
# Usage:
#   ./deploy.sh [--instance ID] [--location LOC] [--ai-location LOC]
#               [--subscription SUB] [--no-fabric] [--no-sql-bootstrap]
#               [--with-vm | --no-vm] [--lab-files-dir DIR] [--no-lab-files] [--yes]
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ----- defaults ------------------------------------------------------------
LOCATION="indonesiacentral"
AI_LOCATION=""                       # auto-pick if empty
AI_LOCATION_PREFS=(eastus2 swedencentral eastus southeastasia)
SUBSCRIPTION=""
DEPLOY_FABRIC=1
DO_SQL_BOOTSTRAP=1
STAGE_LAB_FILES=1
LAB_FILES_DIR="/mnt/c/LabFiles"   # WSL view of Windows C:\LabFiles (Exercise 00, Task 3)
AUTO_YES=0
LAB_INSTANCE_ID=""
BOOTSTRAP_VM_NAME=""                  # override VM used when 1433 is blocked locally
BOOTSTRAP_VM_RG=""                    # resource group of that VM

# Optional Windows lab VM (jumpbox). DEPLOY_VM="" means "ask interactively".
DEPLOY_VM=""
VM_RG="rg-lab513-vm"
VM_NAME="lab513vm"
VM_USER="labadmin"
VM_SIZE="Standard_D2s_v5"
VM_IMAGE="MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest"

CHAT_MODEL="gpt-5";               CHAT_MODEL_VERSION="2025-08-07"
EMBED_MODEL="text-embedding-3-small"; EMBED_MODEL_VERSION="1"
API_VERSION="2025-04-01-preview"
FABRIC_SKU="F2"

# Password protecting the database master key (used to encrypt the DB-scoped
# credential that lets Azure SQL call Azure OpenAI with its managed identity).
MASTER_KEY_PWD="Aa1!MK_$(openssl rand -hex 10 2>/dev/null || echo fallbackMK12345)"

# ----- arg parsing ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance)         LAB_INSTANCE_ID="$2"; shift 2;;
    --location)         LOCATION="$2"; shift 2;;
    --ai-location)      AI_LOCATION="$2"; shift 2;;
    --subscription)     SUBSCRIPTION="$2"; shift 2;;
    --no-fabric)        DEPLOY_FABRIC=0; shift;;
    --no-sql-bootstrap) DO_SQL_BOOTSTRAP=0; shift;;
    --lab-files-dir)    LAB_FILES_DIR="$2"; shift 2;;
    --no-lab-files)     STAGE_LAB_FILES=0; shift;;
    --bootstrap-vm)     BOOTSTRAP_VM_NAME="$2"; shift 2;;
    --bootstrap-vm-rg)  BOOTSTRAP_VM_RG="$2"; shift 2;;
    --with-vm)          DEPLOY_VM=1; shift;;
    --no-vm)            DEPLOY_VM=0; shift;;
    --yes|-y)           AUTO_YES=1; shift;;
    -h|--help)          grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "Unknown argument: $1 (use --help)";;
  esac
done
export AUTO_YES

# ----- preflight -----------------------------------------------------------
hr; log "LAB513 deployment - preflight"; hr
require_cmd az "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
require_cmd curl ""
require_cmd openssl ""
preflight_network
ensure_login

if [[ -n "$SUBSCRIPTION" ]]; then
  log "Setting subscription to '${SUBSCRIPTION}' ..."
  az account set --subscription "$SUBSCRIPTION"
  ensure_login
fi

# ----- names ---------------------------------------------------------------
if [[ -z "$LAB_INSTANCE_ID" ]]; then
  LAB_INSTANCE_ID="$(openssl rand -hex 3)"   # 6 hex chars, e.g. 9f3a2c
fi
LAB_INSTANCE_ID="$(tr '[:upper:]' '[:lower:]' <<<"$LAB_INSTANCE_ID")"

RG="rg-lab513-${LAB_INSTANCE_ID}"
VNET="vnet-lab513-${LAB_INSTANCE_ID}"
SUBNET="snet-lab"
NSG="nsg-lab513-${LAB_INSTANCE_ID}"
SQL_SERVER="faq-ai-assistant-${LAB_INSTANCE_ID}"
SQL_DB="faq-ai-assistant-db"
SQL_ADMIN="admin-${LAB_INSTANCE_ID}"
AIF="aif-lab513-${LAB_INSTANCE_ID}"
FABRIC_CAP="fab${LAB_INSTANCE_ID}"
ENV_FILE="${ROOT_DIR}/.env"
GEN_DIR="${ROOT_DIR}/.generated"

SQL_PASSWORD="$(gen_password)"

# ----- region validation ---------------------------------------------------
hr; log "Validating service availability (honest preflight)"; hr
LOC_DISPLAY="$(region_display_name "$LOCATION")"; LOC_DISPLAY="${LOC_DISPLAY:-$LOCATION}"

if validate_sql_hyperscale "$LOCATION"; then
  ok "Azure SQL Hyperscale available in ${LOC_DISPLAY}."
else
  die "Azure SQL Hyperscale not available in '${LOCATION}'. Pick another --location."
fi

if [[ -z "$AI_LOCATION" ]]; then
  AI_LOCATION="$(pick_ai_location "$CHAT_MODEL" "$EMBED_MODEL" "$CHAT_MODEL_VERSION" "$EMBED_MODEL_VERSION" "${AI_LOCATION_PREFS[@]}")"
fi
ok "AI region (Azure OpenAI / Foundry): ${AI_LOCATION}  [not in ${LOC_DISPLAY}]"

if [[ "$DEPLOY_FABRIC" == "1" ]]; then
  if validate_fabric_region "$LOC_DISPLAY"; then
    ok "Microsoft Fabric capacity available in ${LOC_DISPLAY}."
  else
    warn "Fabric capacity may not be available in ${LOC_DISPLAY}; it will be created in the AI region instead."
  fi
fi

# ----- lab VM choice (interactive unless --with-vm/--no-vm/--yes given) -----
if [[ -z "$DEPLOY_VM" ]]; then
  if [[ "$AUTO_YES" == "1" ]]; then
    DEPLOY_VM=0
    warn "No --with-vm/--no-vm given with --yes; defaulting to NO lab VM."
  elif confirm "Include a Windows lab VM (RDP jumpbox; also bootstraps SQL if port 1433 is blocked locally)?"; then
    DEPLOY_VM=1
  else
    DEPLOY_VM=0
  fi
fi

# ----- plan ----------------------------------------------------------------
hr; printf '%sDeployment plan%s\n' "$C_BOLD" "$C_RESET"; hr
cat <<EOF
  Subscription      : ${CURRENT_SUB_NAME} (${CURRENT_SUB_ID})
  Lab instance id   : ${LAB_INSTANCE_ID}
  Resource group    : ${RG}                 @ ${LOCATION}
  Network           : ${VNET}/${SUBNET} + ${NSG} (ALL INBOUND+OUTBOUND OPEN)
  SQL server / db   : ${SQL_SERVER} / ${SQL_DB}   @ ${LOCATION} (Hyperscale, serverless)
  SQL admin login   : ${SQL_ADMIN}   (password saved to .env, chmod 600)
  AI Foundry        : ${AIF}   @ ${AI_LOCATION}
     - chat model   : ${CHAT_MODEL} (${CHAT_MODEL_VERSION})
     - embed model  : ${EMBED_MODEL} (${EMBED_MODEL_VERSION})
  Fabric capacity   : $([[ $DEPLOY_FABRIC == 1 ]] && echo "${FABRIC_CAP} (${FABRIC_SKU})" || echo "skipped (--no-fabric)")
  Lab VM            : $([[ $DEPLOY_VM == 1 ]] && echo "${VM_NAME} (${VM_SIZE}, Win2022) @ ${LOCATION} in ${VM_RG}" || echo "skipped (no VM)")
  SQL bootstrap     : $([[ $DO_SQL_BOOTSTRAP == 1 ]] && echo "tables + seed + embeddings + SearchFAQ" || echo "skipped (--no-sql-bootstrap)")
  Lab files (Task 3): $([[ $STAGE_LAB_FILES == 1 ]] && echo "stage labfiles/ -> ${LAB_FILES_DIR}" || echo "skipped (--no-lab-files)")

  WARNING: NSG + SQL firewall are wide open (0.0.0.0/0). Lab use only.
EOF
hr
confirm "Proceed with deployment?" || die "Aborted by user."

# ===========================================================================
# 1. Resource group
# ===========================================================================
phase "1/6  Resource group"
az group create -n "$RG" -l "$LOCATION" -o none \
  --tags project=lab513 instance="$LAB_INSTANCE_ID" purpose=workshop
ok "Resource group ${RG} ready."

# ===========================================================================
# 2. Network: VNet + Subnet + NSG with ALL inbound + outbound OPEN
# ===========================================================================
phase "2/6  Network (VNet + Subnet + NSG, all traffic open)"
az network nsg create -g "$RG" -n "$NSG" -l "$LOCATION" -o none

az network nsg rule create -g "$RG" --nsg-name "$NSG" -n AllowAllInbound \
  --priority 100 --direction Inbound --access Allow --protocol '*' \
  --source-address-prefixes '*' --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges '*' -o none
az network nsg rule create -g "$RG" --nsg-name "$NSG" -n AllowAllOutbound \
  --priority 100 --direction Outbound --access Allow --protocol '*' \
  --source-address-prefixes '*' --source-port-ranges '*' \
  --destination-address-prefixes '*' --destination-port-ranges '*' -o none

az network vnet create -g "$RG" -n "$VNET" -l "$LOCATION" \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name "$SUBNET" --subnet-prefixes 10.0.1.0/24 \
  --nsg "$NSG" -o none
ok "VNet/${SUBNET} created and NSG ${NSG} attached (all inbound+outbound = Allow)."

# ===========================================================================
# 3. Azure SQL Hyperscale (serverless) + open firewall
# ===========================================================================
phase "3/6  Azure SQL Hyperscale"
az sql server create -g "$RG" -n "$SQL_SERVER" -l "$LOCATION" \
  --admin-user "$SQL_ADMIN" --admin-password "$SQL_PASSWORD" \
  --assign-identity --identity-type SystemAssigned \
  --enable-public-network true -o none
ok "SQL server ${SQL_SERVER} created (with system-assigned managed identity)."

# Allow all Azure services + (lab) all client IPs.
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" \
  -n AllowAllAzure --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none
az sql server firewall-rule create -g "$RG" -s "$SQL_SERVER" \
  -n AllowAllIPs-LABONLY --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255 -o none
warn "SQL firewall opened to 0.0.0.0-255.255.255.255 (lab only)."

# Hyperscale, serverless, 2 vCores (cheapest practical for the lab).
az sql db create -g "$RG" -s "$SQL_SERVER" -n "$SQL_DB" \
  --edition Hyperscale --family Gen5 --capacity 2 \
  --compute-model Serverless --ha-replicas 0 \
  --backup-storage-redundancy Local -o none
ok "Database ${SQL_DB} created (Hyperscale serverless, HS_S_Gen5_2)."

# ===========================================================================
# 4. Azure AI Foundry (AIServices) + model deployments
# ===========================================================================
phase "4/6  Azure AI Foundry + models (@ ${AI_LOCATION})"
if az cognitiveservices account show -g "$RG" -n "$AIF" -o none 2>/dev/null; then
  ok "AI Foundry resource ${AIF} already exists."
else
  az cognitiveservices account create -g "$RG" -n "$AIF" -l "$AI_LOCATION" \
    --kind AIServices --sku S0 --custom-domain "$AIF" \
    --assign-identity --yes -o none
  ok "AI Foundry resource ${AIF} created."
fi

az cognitiveservices account deployment create -g "$RG" -n "$AIF" \
  --deployment-name "$CHAT_MODEL" \
  --model-name "$CHAT_MODEL" --model-version "$CHAT_MODEL_VERSION" \
  --model-format OpenAI --sku-name GlobalStandard --sku-capacity 20 -o none
ok "Deployed chat model ${CHAT_MODEL}."

az cognitiveservices account deployment create -g "$RG" -n "$AIF" \
  --deployment-name "$EMBED_MODEL" \
  --model-name "$EMBED_MODEL" --model-version "$EMBED_MODEL_VERSION" \
  --model-format OpenAI --sku-name GlobalStandard --sku-capacity 50 -o none
ok "Deployed embedding model ${EMBED_MODEL}."

# Foundry project the lab refers to (Exercise 4): FAQ-Assistant-project.
# Pre-provisioned here so the agent has a project + gpt-5 deployment ready.
# NOTE: pass the body INLINE (not @file) — Windows az.exe cannot read a WSL
# path for @file, which silently produced an empty project on earlier runs.
FOUNDRY_PROJECT="FAQ-Assistant-project"
PROJ_URL="https://management.azure.com/subscriptions/${CURRENT_SUB_ID}/resourceGroups/${RG}/providers/Microsoft.CognitiveServices/accounts/${AIF}/projects/${FOUNDRY_PROJECT}?api-version=2025-04-01-preview"
PROJ_BODY="{\"location\":\"${AI_LOCATION}\",\"identity\":{\"type\":\"SystemAssigned\"},\"properties\":{}}"
if az rest --method put --url "$PROJ_URL" --headers Content-Type=application/json \
     --body "$PROJ_BODY" -o none; then
  ok "Foundry project ${FOUNDRY_PROJECT} created (with gpt-5 available)."
else
  warn "Could not create Foundry project ${FOUNDRY_PROJECT} via CLI; create it at https://ai.azure.com/"
fi

AI_ENDPOINT=$(az cognitiveservices account show -g "$RG" -n "$AIF" \
  --query properties.endpoint -o tsv)
AI_KEY=$(az cognitiveservices account keys list -g "$RG" -n "$AIF" \
  --query key1 -o tsv 2>/dev/null || echo "")
# Base account URL (no trailing slash) - used as the DB-scoped credential name.
AI_ACCOUNT_URL="${AI_ENDPOINT%/}"
EMBED_URL="${AI_ENDPOINT}openai/deployments/${EMBED_MODEL}/embeddings?api-version=${API_VERSION}"
CHAT_URL="${AI_ENDPOINT}openai/deployments/${CHAT_MODEL}/chat/completions?api-version=${API_VERSION}"

# Grant the SQL server's managed identity token access to Azure OpenAI so it can
# call the embeddings endpoint without an api-key (Entra token auth).
SQL_MI_PRINCIPAL=$(az sql server show -g "$RG" -n "$SQL_SERVER" \
  --query identity.principalId -o tsv 2>/dev/null || echo "")
AIF_ID=$(az cognitiveservices account show -g "$RG" -n "$AIF" --query id -o tsv)
if [[ -n "$SQL_MI_PRINCIPAL" ]]; then
  az role assignment create \
    --assignee-object-id "$SQL_MI_PRINCIPAL" --assignee-principal-type ServicePrincipal \
    --role "Cognitive Services OpenAI User" --scope "$AIF_ID" -o none 2>/dev/null \
    && ok "Granted SQL managed identity 'Cognitive Services OpenAI User' on ${AIF}." \
    || warn "Role assignment for SQL managed identity may already exist."
else
  warn "Could not resolve SQL server managed identity principalId; embeddings may fail."
fi

# ===========================================================================
# 5. Microsoft Fabric capacity (optional)
# ===========================================================================
if [[ "$DEPLOY_FABRIC" == "1" ]]; then
  phase "5/6  Microsoft Fabric capacity (${FABRIC_SKU})"
  FABRIC_LOC="$LOCATION"
  validate_fabric_region "$LOC_DISPLAY" || FABRIC_LOC="$AI_LOCATION"
  ADMIN_UPN=$(az account show --query user.name -o tsv)
  if az fabric capacity create -g "$RG" -n "$FABRIC_CAP" -l "$FABRIC_LOC" \
        --sku "{name:${FABRIC_SKU},tier:Fabric}" \
        --administration "{members:[${ADMIN_UPN}]}" -o none 2>/dev/null; then
    ok "Fabric capacity ${FABRIC_CAP} created in ${FABRIC_LOC}."
  else
    warn "Fabric capacity could not be created via CLI (the 'az fabric' extension"
    warn "may be missing, or your tenant requires portal-based purchase)."
    warn "Install with:  az extension add --name microsoft-fabric"
    warn "Or use a Fabric Trial capacity for Exercise 5 (see TASKS.md)."
    DEPLOY_FABRIC=0
  fi
else
  phase "5/6  Microsoft Fabric capacity - skipped"
fi

# ===========================================================================
# Lab VM (optional) - Windows jumpbox (RDP) that also reaches SQL on 1433 from
# inside Azure, so the SQL bootstrap can be delegated to it when this host's
# outbound 1433 is blocked. Created in a SEPARATE resource group (VM_RG).
# ===========================================================================
if [[ "$DEPLOY_VM" == "1" ]]; then
  phase "Lab VM (Windows jumpbox @ ${VM_RG})"
  az group create -n "$VM_RG" -l "$LOCATION" -o none \
    --tags project=lab513 instance="$LAB_INSTANCE_ID" purpose=lab-vm
  if az vm show -g "$VM_RG" -n "$VM_NAME" -o none 2>/dev/null; then
    ok "Lab VM ${VM_NAME} already exists (reusing)."
  else
    VM_PWD="$(gen_password)"
    # Random DNS suffix via openssl (no pipe -> avoids SIGPIPE under set -o pipefail).
    VM_DNS="${VM_NAME}$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)"
    az vm create -g "$VM_RG" -n "$VM_NAME" -l "$LOCATION" \
      --image "$VM_IMAGE" --size "$VM_SIZE" \
      --admin-username "$VM_USER" --admin-password "$VM_PWD" \
      --public-ip-sku Standard --public-ip-address-dns-name "$VM_DNS" \
      --nsg-rule RDP -o none
    ok "Lab VM ${VM_NAME} created (${VM_SIZE}, Windows Server 2022)."
    VM_IP=$(az vm show -d -g "$VM_RG" -n "$VM_NAME" --query publicIps -o tsv 2>/dev/null || echo "")
    VM_FQDN=$(az network public-ip list -g "$VM_RG" --query "[0].dnsSettings.fqdn" -o tsv 2>/dev/null || echo "")
    umask 077
    printf 'VM=%s RG=%s LOC=%s USER=%s PASSWORD=%s IP=%s FQDN=%s\n' \
      "$VM_NAME" "$VM_RG" "$LOCATION" "$VM_USER" "$VM_PWD" "$VM_IP" "$VM_FQDN" > "${ROOT_DIR}/.vm-cred"
    chmod 600 "${ROOT_DIR}/.vm-cred"
    ok "VM credentials saved to ${ROOT_DIR}/.vm-cred (chmod 600)."
    if [[ -f "${SCRIPT_DIR}/install-tools.ps1" ]]; then
      log "Installing VS Code + Azure CLI on the VM (best effort, may take a few minutes) ..."
      if az vm run-command invoke -g "$VM_RG" -n "$VM_NAME" --command-id RunPowerShellScript \
            --scripts "$(cat "${SCRIPT_DIR}/install-tools.ps1")" -o none 2>/dev/null; then
        ok "VM tooling installed (VS Code + Azure CLI)."
      else
        warn "VM tooling install skipped/failed (non-fatal) - install manually on the VM if needed."
      fi
    fi
  fi
  # Let the SQL bootstrap auto-delegate to this VM when 1433 is blocked locally.
  [[ -z "$BOOTSTRAP_VM_NAME" ]] && BOOTSTRAP_VM_NAME="$VM_NAME"
  [[ -z "$BOOTSTRAP_VM_RG"   ]] && BOOTSTRAP_VM_RG="$VM_RG"
else
  phase "Lab VM - skipped (no VM)"
fi

# ===========================================================================
# 6. Write .env (secrets, chmod 600)
# ===========================================================================
phase "6/6  Writing .env"
umask 077
cat > "$ENV_FILE" <<EOF
# LAB513 deployment outputs - generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Contains secrets. Do NOT commit. (chmod 600)
LAB_INSTANCE_ID=${LAB_INSTANCE_ID}
SUBSCRIPTION_ID=${CURRENT_SUB_ID}
RESOURCE_GROUP=${RG}
LOCATION=${LOCATION}
AI_LOCATION=${AI_LOCATION}

SQL_SERVER=${SQL_SERVER}
SQL_FQDN=${SQL_SERVER}.database.windows.net
SQL_DB=${SQL_DB}
SQL_ADMIN=${SQL_ADMIN}
SQL_PASSWORD=${SQL_PASSWORD}

AI_FOUNDRY=${AIF}
AI_ENDPOINT=${AI_ENDPOINT}
AI_KEY=${AI_KEY}
CHAT_MODEL=${CHAT_MODEL}
EMBED_MODEL=${EMBED_MODEL}
CHAT_URL=${CHAT_URL}
EMBED_URL=${EMBED_URL}
API_VERSION=${API_VERSION}

FABRIC_CAPACITY=$([[ $DEPLOY_FABRIC == 1 ]] && echo "$FABRIC_CAP" || echo "")
EOF
chmod 600 "$ENV_FILE"
ok "Outputs written to ${ENV_FILE} (chmod 600)."

# ===========================================================================
# SQL bootstrap (tables + seed + embeddings + SearchFAQ)
# ===========================================================================
if [[ "$DO_SQL_BOOTSTRAP" == "1" ]]; then
  phase "SQL bootstrap"
  mkdir -p "$GEN_DIR"; chmod 700 "$GEN_DIR"
  # Resolve sqlcmd: prefer the one on PATH, else auto-download portable go-sqlcmd.
  if command -v sqlcmd >/dev/null 2>&1; then
    SQLCMD_BIN="sqlcmd"
  else
    SQLCMD_BIN="${GEN_DIR}/sqlcmd"
    if [[ ! -x "$SQLCMD_BIN" ]]; then
      warn "'sqlcmd' not on PATH - downloading portable go-sqlcmd ..."
      # go-sqlcmd ships as a tarball (sqlcmd-linux-amd64.tar.bz2), not a raw binary.
      _arch="$(uname -m)"; case "$_arch" in aarch64|arm64) _sqlcmd_arch="arm64" ;; *) _sqlcmd_arch="amd64" ;; esac
      _tarball="${GEN_DIR}/sqlcmd.tar.bz2"
      curl -fsSL -o "$_tarball" \
        "https://github.com/microsoft/go-sqlcmd/releases/download/v1.8.0/sqlcmd-linux-${_sqlcmd_arch}.tar.bz2" \
        || die "Could not download go-sqlcmd. Install sqlcmd manually, then run ${SCRIPT_DIR}/run-sql-bootstrap.sh"
      # Extract 'sqlcmd' from the bz2 tarball. Prefer tar (needs bzip2); fall back to
      # python3 (bz2 + tarfile are stdlib) for hosts without bzip2 installed.
      if tar -xjf "$_tarball" -C "$GEN_DIR" sqlcmd 2>/dev/null; then
        :
      elif command -v python3 >/dev/null 2>&1 && \
        python3 - "$_tarball" "$GEN_DIR" <<'PY'
import sys, tarfile
tarball, dest = sys.argv[1], sys.argv[2]
with tarfile.open(tarball, "r:bz2") as t:
    t.extract("sqlcmd", dest)
PY
      then
        :
      else
        die "Could not extract go-sqlcmd (need 'bzip2' for tar, or 'python3'). Install sqlcmd manually."
      fi
      chmod +x "$SQLCMD_BIN"
      rm -f "$_tarball"
    fi
    ok "Using portable sqlcmd: ${SQLCMD_BIN}"
  fi
  if true; then
    # Render templated SQL with the live endpoint + managed-identity settings.
    sed -e "s|@@EMBED_URL@@|${EMBED_URL}|g" \
        -e "s|@@AI_ACCOUNT_URL@@|${AI_ACCOUNT_URL}|g" \
        -e "s|@@MASTER_KEY_PWD@@|${MASTER_KEY_PWD}|g" \
        "${ROOT_DIR}/sql/03_generate_embeddings.sql" > "${GEN_DIR}/03_generate_embeddings.sql"
    sed -e "s|@@EMBED_URL@@|${EMBED_URL}|g" \
        -e "s|@@AI_ACCOUNT_URL@@|${AI_ACCOUNT_URL}|g" \
        "${ROOT_DIR}/sql/04_search_proc.sql" > "${GEN_DIR}/04_search_proc.sql"
    sed -e "s|@@EMBED_URL@@|${EMBED_URL}|g" \
        -e "s|@@AI_ACCOUNT_URL@@|${AI_ACCOUNT_URL}|g" \
        "${ROOT_DIR}/sql/05_external_model.sql" > "${GEN_DIR}/05_external_model.sql"
    # 06 is an interactive Exercise 3 (RAG) script — rendered for the audience to
    # run manually (mssql extension / portal Query editor), NOT auto-executed.
    sed -e "s|@@CHAT_URL@@|${CHAT_URL}|g" \
        -e "s|@@AI_ACCOUNT_URL@@|${AI_ACCOUNT_URL}|g" \
        "${ROOT_DIR}/sql/06_rag_chat.sql" > "${GEN_DIR}/06_rag_chat.sql"
    chmod 600 "${GEN_DIR}"/*.sql

    # SQL files in apply order (schema -> seed -> proc -> embeddings -> ext model).
    SQL_FILES=( "${ROOT_DIR}/sql/01_schema.sql"
                "${ROOT_DIR}/sql/02_seed_faq.sql"
                "${GEN_DIR}/04_search_proc.sql"
                "${GEN_DIR}/03_generate_embeddings.sql"
                "${GEN_DIR}/05_external_model.sql" )

    # Connectivity-aware execution. Many corp/ISP networks (and WSL behind
    # Global Secure Access) block outbound TCP 1433, so sqlcmd from this host
    # times out even with the SQL firewall wide open. Detect that and delegate
    # the bootstrap to an Azure VM, which reaches 1433 over the Azure backbone.
    # Never let a bootstrap failure abort the rest of the deploy (lab files +
    # credentials must still run), so guard with set +e.
    set +e
    if tcp_port_open "${SQL_SERVER}.database.windows.net" 1433; then
      ok "TCP 1433 reachable from this host - running SQL bootstrap locally."
      SQLCMD=("$SQLCMD_BIN" -S "tcp:${SQL_SERVER}.database.windows.net,1433" -d "$SQL_DB"
              -U "$SQL_ADMIN" -P "$SQL_PASSWORD" -C -l 60)
      log "Applying 01_schema.sql ..."           ; "${SQLCMD[@]}" -i "${ROOT_DIR}/sql/01_schema.sql"
      log "Applying 02_seed_faq.sql ..."         ; "${SQLCMD[@]}" -i "${ROOT_DIR}/sql/02_seed_faq.sql"
      log "Applying 04_search_proc.sql ..."      ; "${SQLCMD[@]}" -i "${GEN_DIR}/04_search_proc.sql"
      log "Generating embeddings (calls Azure OpenAI) ..." ; "${SQLCMD[@]}" -i "${GEN_DIR}/03_generate_embeddings.sql"
      log "Registering external model (Exercise 2) ..."     ; "${SQLCMD[@]}" -i "${GEN_DIR}/05_external_model.sql"
      ok "SQL bootstrap complete (FAQ_Content, FAQ_Embeddings, dbo.SearchFAQ ready)."
    else
      warn "TCP 1433 BLOCKED from this host (corp/ISP/GSA egress). Delegating bootstrap to an Azure VM ..."
      if [[ -n "$BOOTSTRAP_VM_NAME" && -n "$BOOTSTRAP_VM_RG" ]]; then
        _VM_RG="$BOOTSTRAP_VM_RG"; _VM_NAME="$BOOTSTRAP_VM_NAME"
      else
        _VM_INFO="$(detect_bootstrap_vm)"
        _VM_RG="$(printf '%s' "$_VM_INFO" | cut -f1)"
        _VM_NAME="$(printf '%s' "$_VM_INFO" | cut -f2)"
      fi
      if [[ -n "$_VM_NAME" && -n "$_VM_RG" ]]; then
        log "Running SQL bootstrap on VM '${_VM_NAME}' (rg ${_VM_RG}) via az vm run-command ..."
        if run_sql_files_via_vm "$_VM_RG" "$_VM_NAME" \
              "$SQL_SERVER" "$SQL_DB" "$SQL_ADMIN" "$SQL_PASSWORD" "${SQL_FILES[@]}"; then
          ok "SQL bootstrap complete on VM ${_VM_NAME} (FAQ_Content, FAQ_Embeddings, dbo.SearchFAQ ready)."
        else
          warn "VM-delegated bootstrap did not confirm success (see message above)."
          warn "Rendered SQL is in ${GEN_DIR} (01/02 in ${ROOT_DIR}/sql); run it from any host that can reach 1433."
        fi
      else
        warn "1433 is blocked here and no running Windows VM was found to delegate to."
        warn "Start the lab VM (or pass --bootstrap-vm NAME --bootstrap-vm-rg RG), then re-run:"
        warn "  ${SCRIPT_DIR}/deploy.sh --instance ${LAB_INSTANCE_ID} --yes"
        warn "Rendered SQL files are ready in ${GEN_DIR} (01/02 in ${ROOT_DIR}/sql)."
      fi
    fi
    set -e
    log "Exercise 3 (RAG) script ready to run MANUALLY: ${GEN_DIR}/06_rag_chat.sql (token auth, gpt-5)."
  fi
fi

# ===========================================================================
# Stage lab files into C:\LabFiles  (Exercise 00, Task 3)
#   Mirrors the repo's lab513/labfiles/ tree to the Windows working paths the
#   lab expects:  C:\LabFiles\sql_mcp_server  and  C:\LabFiles\sql-mcp-lab
# ===========================================================================
if [[ "$STAGE_LAB_FILES" == "1" ]]; then
  phase "Staging lab files -> ${LAB_FILES_DIR} (Exercise 00, Task 3)"
  if [[ ! -d "${ROOT_DIR}/labfiles" ]]; then
    warn "Source ${ROOT_DIR}/labfiles not found - skipping lab-file staging."
  elif mkdir -p "${LAB_FILES_DIR}" 2>/dev/null \
        && cp -R "${ROOT_DIR}/labfiles/sql_mcp_server" "${LAB_FILES_DIR}/" 2>/dev/null \
        && cp -R "${ROOT_DIR}/labfiles/sql-mcp-lab"    "${LAB_FILES_DIR}/" 2>/dev/null; then
    ok "Lab files staged: ${LAB_FILES_DIR}/sql_mcp_server and ${LAB_FILES_DIR}/sql-mcp-lab."
  else
    warn "Could not stage lab files to ${LAB_FILES_DIR} (path not writable from this shell?)."
    warn "Copy them manually:  cp -R ${ROOT_DIR}/labfiles/* <your C:\\LabFiles path>"
  fi
else
  phase "Lab-file staging - skipped (--no-lab-files)"
fi

# ===========================================================================
# Done
# ===========================================================================
print_timing_summary
hr; ok "LAB513 deployment finished."; hr

# ----- consolidated credentials (VM + SQL) ---------------------------------
# Workshop requirement: after deploy, always surface BOTH the lab VM login and
# the Azure SQL login (password included). Secrets also live in .env / .vm-cred.
VM_CRED_FILE="${ROOT_DIR}/.vm-cred"
hr; printf '%sCREDENTIALS (also saved to .env / .vm-cred)%s\n' "$C_BOLD" "$C_RESET"; hr
printf '%s1) Lab VM (RDP)%s\n' "$C_BOLD" "$C_RESET"
if [[ -f "$VM_CRED_FILE" ]]; then
  # PowerShell Out-File adds a BOM / UTF-16 bytes; keep only printable chars.
  VM_LINE="$(tr -cd '[:print:]\n' < "$VM_CRED_FILE")"
  for kv in $VM_LINE; do
    case "$kv" in
      USER=*)     printf '   User     : %s\n' "${kv#USER=}";;
      PASSWORD=*) printf '   Password : %s\n' "${kv#PASSWORD=}";;
      IP=*)       printf '   Public IP: %s   (RDP 3389)\n' "${kv#IP=}";;
      FQDN=*)     printf '   FQDN     : %s\n' "${kv#FQDN=}";;
    esac
  done
else
  printf '   (.vm-cred not found - run scripts/create-vm.ps1 to create the VM)\n'
fi
printf '%s2) Azure SQL%s\n' "$C_BOLD" "$C_RESET"
printf '   Server   : %s.database.windows.net\n' "$SQL_SERVER"
printf '   Database : %s\n' "$SQL_DB"
printf '   Login    : %s\n' "$SQL_ADMIN"
printf '   Password : %s\n' "$SQL_PASSWORD"
hr

cat <<EOF
  Next steps:
    1. Review outputs:        cat ${ENV_FILE}
    2. Follow the runbook:    ${ROOT_DIR}/TASKS.md
    3. Tear everything down:  ${SCRIPT_DIR}/teardown.sh --instance ${LAB_INSTANCE_ID}

  SQL connection (Exercise 1):
    Server : ${SQL_SERVER}.database.windows.net
    Db     : ${SQL_DB}
    Login  : ${SQL_ADMIN}   (password in .env)
EOF
