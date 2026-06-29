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
#   - Azure AI Foundry (AIServices) + gpt-4o + text-embedding-3-small (southeastasia)
#   - Microsoft Fabric capacity (F2)         (indonesiacentral, optional)
#   - SQL bootstrap: tables, FAQ seed, embeddings, dbo.SearchFAQ (optional)
#
# SECURITY: the NSG and SQL firewall are intentionally wide open for a short-
# lived lab. This is INSECURE. Run ./teardown.sh as soon as you are done.
#
# Usage:
#   ./deploy.sh [--instance ID] [--location LOC] [--ai-location LOC]
#               [--subscription SUB] [--no-fabric] [--no-sql-bootstrap]
#               [--lab-files-dir DIR] [--no-lab-files] [--yes]
# ===========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# ----- defaults ------------------------------------------------------------
LOCATION="indonesiacentral"
AI_LOCATION=""                       # auto-pick if empty
AI_LOCATION_PREFS=(southeastasia swedencentral eastus2 eastus)
SUBSCRIPTION=""
DEPLOY_FABRIC=1
DO_SQL_BOOTSTRAP=1
STAGE_LAB_FILES=1
LAB_FILES_DIR="/mnt/c/LabFiles"   # WSL view of Windows C:\LabFiles (Exercise 00, Task 3)
AUTO_YES=0
LAB_INSTANCE_ID=""

CHAT_MODEL="gpt-4o";               CHAT_MODEL_VERSION="2024-11-20"
EMBED_MODEL="text-embedding-3-small"; EMBED_MODEL_VERSION="1"
API_VERSION="2024-10-21"
FABRIC_SKU="F2"

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
  AI_LOCATION="$(pick_ai_location "$CHAT_MODEL" "$EMBED_MODEL" "${AI_LOCATION_PREFS[@]}")"
fi
ok "AI region (Azure OpenAI / Foundry): ${AI_LOCATION}  [not in ${LOC_DISPLAY}]"

if [[ "$DEPLOY_FABRIC" == "1" ]]; then
  if validate_fabric_region "$LOC_DISPLAY"; then
    ok "Microsoft Fabric capacity available in ${LOC_DISPLAY}."
  else
    warn "Fabric capacity may not be available in ${LOC_DISPLAY}; it will be created in the AI region instead."
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
  SQL bootstrap     : $([[ $DO_SQL_BOOTSTRAP == 1 ]] && echo "tables + seed + embeddings + SearchFAQ" || echo "skipped (--no-sql-bootstrap)")
  Lab files (Task 3): $([[ $STAGE_LAB_FILES == 1 ]] && echo "stage labfiles/ -> ${LAB_FILES_DIR}" || echo "skipped (--no-lab-files)")

  WARNING: NSG + SQL firewall are wide open (0.0.0.0/0). Lab use only.
EOF
hr
confirm "Proceed with deployment?" || die "Aborted by user."

# ===========================================================================
# 1. Resource group
# ===========================================================================
hr; log "1/6  Resource group"; hr
az group create -n "$RG" -l "$LOCATION" -o none \
  --tags project=lab513 instance="$LAB_INSTANCE_ID" purpose=workshop
ok "Resource group ${RG} ready."

# ===========================================================================
# 2. Network: VNet + Subnet + NSG with ALL inbound + outbound OPEN
# ===========================================================================
hr; log "2/6  Network (VNet + Subnet + NSG, all traffic open)"; hr
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
hr; log "3/6  Azure SQL Hyperscale"; hr
az sql server create -g "$RG" -n "$SQL_SERVER" -l "$LOCATION" \
  --admin-user "$SQL_ADMIN" --admin-password "$SQL_PASSWORD" \
  --enable-public-network true -o none
ok "SQL server ${SQL_SERVER} created."

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
hr; log "4/6  Azure AI Foundry + models (@ ${AI_LOCATION})"; hr
az cognitiveservices account create -g "$RG" -n "$AIF" -l "$AI_LOCATION" \
  --kind AIServices --sku S0 --custom-domain "$AIF" \
  --assign-identity --yes -o none
ok "AI Foundry resource ${AIF} created."

az cognitiveservices account deployment create -g "$RG" -n "$AIF" \
  --deployment-name "$CHAT_MODEL" \
  --model-name "$CHAT_MODEL" --model-version "$CHAT_MODEL_VERSION" \
  --model-format OpenAI --sku-name GlobalStandard --sku-capacity 20 -o none
ok "Deployed chat model ${CHAT_MODEL}."

az cognitiveservices account deployment create -g "$RG" -n "$AIF" \
  --deployment-name "$EMBED_MODEL" \
  --model-name "$EMBED_MODEL" --model-version "$EMBED_MODEL_VERSION" \
  --model-format OpenAI --sku-name Standard --sku-capacity 50 -o none
ok "Deployed embedding model ${EMBED_MODEL}."

AI_ENDPOINT=$(az cognitiveservices account show -g "$RG" -n "$AIF" \
  --query properties.endpoint -o tsv)
AI_KEY=$(az cognitiveservices account keys list -g "$RG" -n "$AIF" \
  --query key1 -o tsv)
EMBED_URL="${AI_ENDPOINT}openai/deployments/${EMBED_MODEL}/embeddings?api-version=${API_VERSION}"
CHAT_URL="${AI_ENDPOINT}openai/deployments/${CHAT_MODEL}/chat/completions?api-version=${API_VERSION}"

# ===========================================================================
# 5. Microsoft Fabric capacity (optional)
# ===========================================================================
if [[ "$DEPLOY_FABRIC" == "1" ]]; then
  hr; log "5/6  Microsoft Fabric capacity (${FABRIC_SKU})"; hr
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
  hr; log "5/6  Microsoft Fabric capacity - skipped"; hr
fi

# ===========================================================================
# 6. Write .env (secrets, chmod 600)
# ===========================================================================
hr; log "6/6  Writing .env"; hr
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
  hr; log "SQL bootstrap"; hr
  mkdir -p "$GEN_DIR"; chmod 700 "$GEN_DIR"
  # Resolve sqlcmd: prefer the one on PATH, else auto-download portable go-sqlcmd.
  if command -v sqlcmd >/dev/null 2>&1; then
    SQLCMD_BIN="sqlcmd"
  else
    SQLCMD_BIN="${GEN_DIR}/sqlcmd"
    if [[ ! -x "$SQLCMD_BIN" ]]; then
      warn "'sqlcmd' not on PATH - downloading portable go-sqlcmd ..."
      curl -fsSL -o "$SQLCMD_BIN" \
        https://github.com/microsoft/go-sqlcmd/releases/download/v1.8.0/sqlcmd-linux-amd64 \
        && chmod +x "$SQLCMD_BIN" \
        || die "Could not download go-sqlcmd. Install sqlcmd manually, then run ${SCRIPT_DIR}/run-sql-bootstrap.sh"
    fi
    ok "Using portable sqlcmd: ${SQLCMD_BIN}"
  fi
  if true; then
    # Render templated SQL with the live endpoint/key/deployment.
    sed -e "s|@@EMBED_URL@@|${EMBED_URL}|g" \
        -e "s|@@AI_KEY@@|${AI_KEY}|g" \
        "${ROOT_DIR}/sql/03_generate_embeddings.sql" > "${GEN_DIR}/03_generate_embeddings.sql"
    sed -e "s|@@EMBED_URL@@|${EMBED_URL}|g" \
        -e "s|@@AI_KEY@@|${AI_KEY}|g" \
        "${ROOT_DIR}/sql/04_search_proc.sql" > "${GEN_DIR}/04_search_proc.sql"
    chmod 600 "${GEN_DIR}"/*.sql

    SQLCMD=("$SQLCMD_BIN" -S "tcp:${SQL_SERVER}.database.windows.net,1433" -d "$SQL_DB"
            -U "$SQL_ADMIN" -P "$SQL_PASSWORD" -C -l 60)
    log "Applying 01_schema.sql ..."           ; "${SQLCMD[@]}" -i "${ROOT_DIR}/sql/01_schema.sql"
    log "Applying 02_seed_faq.sql ..."         ; "${SQLCMD[@]}" -i "${ROOT_DIR}/sql/02_seed_faq.sql"
    log "Applying 04_search_proc.sql ..."      ; "${SQLCMD[@]}" -i "${GEN_DIR}/04_search_proc.sql"
    log "Generating embeddings (calls Azure OpenAI) ..." ; "${SQLCMD[@]}" -i "${GEN_DIR}/03_generate_embeddings.sql"
    ok "SQL bootstrap complete (FAQ_Content, FAQ_Embeddings, dbo.SearchFAQ ready)."
  fi
fi

# ===========================================================================
# Stage lab files into C:\LabFiles  (Exercise 00, Task 3)
#   Mirrors the repo's lab513/labfiles/ tree to the Windows working paths the
#   lab expects:  C:\LabFiles\sql_mcp_server  and  C:\LabFiles\sql-mcp-lab
# ===========================================================================
if [[ "$STAGE_LAB_FILES" == "1" ]]; then
  hr; log "Staging lab files -> ${LAB_FILES_DIR} (Exercise 00, Task 3)"; hr
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
  hr; log "Lab-file staging - skipped (--no-lab-files)"; hr
fi

# ===========================================================================
# Done
# ===========================================================================
hr; ok "LAB513 deployment finished."; hr
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
