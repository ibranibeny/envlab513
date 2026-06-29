# envlab513 — Build26-LAB513 self-host

Self-hosted setup for **LAB513 — Build an AI app with Azure SQL Hyperscale, Microsoft Fabric, and Microsoft Foundry** on your own Azure subscription. This repo provisions the lab, loads the FAQ data, stages the local lab files, and verifies Exercise-00 readiness.

Reference: [microsoft/Build26-LAB513 · exercise-00.md](https://github.com/microsoft/Build26-LAB513-build-an-ai-app-with-azure-sql-hyperscale-microsoft-fabric-foundry/blob/main/docs/Lab/Instructions/exercise-00.md)

## Layout

| Path | Purpose |
|---|---|
| `scripts/deploy.sh` | Provision RG, VNet, SQL Hyperscale, AI Foundry + models + `FAQ-Assistant-project`, Fabric |
| `scripts/teardown.sh` | Delete RG + purge AI account + clean local secrets |
| `scripts/install-tools.ps1` | VM bootstrap: VS Code, Azure CLI, Git, Python 3.12, devtunnel |
| `scripts/create-vm.ps1` | Create lab VM and run `install-tools.ps1` |
| `sql/01..04_*.sql` | FAQ schema, seed, embeddings, `dbo.SearchFAQ` |
| `labfiles/sql_mcp_server/` | MCP server (`server.py`, `requirements.txt`) → staged to `C:\LabFiles` |
| `labfiles/sql-mcp-lab/` | DAB config + VS Code MCP wiring → staged to `C:\LabFiles` |
| `REPORT.md` | Honest as-built report (regions, security, cost) |

## Prerequisites

Before you run anything, make sure the host (lab VM or your machine) has:

| Requirement | How to get / verify | Why |
|---|---|---|
| **Git on PowerShell** | Install from [git-scm.com](https://git-scm.com/download/win), then in PowerShell run `git --version`. If not found, add it to PATH for the session: `$env:Path += ';C:\Program Files\Git\cmd'` | Clone this repo and commit lab work |
| **Azure CLI + device-code login** | Install Azure CLI, then sign in with **device code** (no browser popup needed): `az login --use-device-code` — open the shown URL, enter the code, pick the account `bibrani@MngEnvMCAP708029.onmicrosoft.com` | `deploy.sh` / `teardown.sh` provision Azure resources |
| **Azure subscription with Contributor** | `az account set --subscription "ME-MngEnvMCAP708029-benyibrani-1"` then `az account show` | Create RG, SQL, AI Foundry, Fabric |
| **GitHub Enterprise + Copilot** | A GitHub account enrolled in your org's **GitHub Enterprise** with **Copilot** enabled; sign in inside VS Code (Accounts → Sign in) | Exercise 2 uses GitHub Copilot to write the semantic-search query |
| **VS Code + extensions** | VS Code with the **GitHub Copilot**, **SQL Server (mssql)**, and **Azure** extensions | Authoring + running SQL / Copilot prompts |

> Device-code tip: if `az login` can't open a browser on the VM, always use `az login --use-device-code` and complete the code on any machine.

## What gets installed / provisioned

**Installed on the lab VM** by `scripts/install-tools.ps1` (via `create-vm.ps1`):

| Tool | Version target | Purpose |
|---|---|---|
| Visual Studio Code | latest | Editor + Copilot + MCP |
| Azure CLI | latest | Provision + manage Azure |
| Git | latest | Clone repo, commit work |
| Python | 3.12 | MCP server (`server.py`) |
| devtunnel | latest | Expose local MCP endpoint (Exercise 4) |
| .NET SDK | latest | DAB (Data API Builder) |

**Provisioned in Azure** by `scripts/deploy.sh`:

| Service | SKU / detail | Region |
|---|---|---|
| Resource group + VNet / Subnet / NSG | lab networking | `indonesiacentral` |
| Azure SQL logical server + **Hyperscale** DB | Serverless, Gen5 2 vCore, system-assigned Managed Identity | `indonesiacentral` |
| **Azure AI Foundry** + `gpt-4o` + `text-embedding-3-small` + `FAQ-Assistant-project` | token-only auth (`disableLocalAuth=true`) | `southeastasia`/`eastus2` (Azure OpenAI not in Indonesia Central) |
| Microsoft Fabric capacity | F2 (skippable with `--no-fabric`) | `indonesiacentral` (fallback `southeastasia`) |

> Cost note: the **Fabric F2 capacity bills continuously** — run `deploy.sh --no-fabric` or `teardown.sh` when not using Exercise 5.

## Quick start on the lab VM

```powershell
# refresh PATH if Git was just installed
$env:Path += ';C:\Program Files\Git\cmd'

git clone https://github.com/ibranibeny/envlab513.git C:\Lab\envlab513
New-Item -ItemType Directory -Force C:\LabFiles | Out-Null
Copy-Item C:\Lab\envlab513\labfiles\* C:\LabFiles\ -Recurse -Force
```

Lab files must live at the paths Exercise-00 checks: `C:\LabFiles\sql_mcp_server` and `C:\LabFiles\sql-mcp-lab`.

## Provision (deploy.sh)

```bash
./scripts/deploy.sh --instance <LAB_INSTANCE_ID> --ai-location eastus2
./scripts/teardown.sh   # when finished — controls cost
```

## Exercise-00 readiness

| Item | Status |
|---|---|
| VS Code + SQL / Copilot extensions | ✅ |
| `python`, `pip`, `dotnet`, `devtunnel` | ✅ |
| `C:\LabFiles\sql_mcp_server` (`server.py`, `requirements.txt`) | ✅ |
| Azure SQL Hyperscale + FAQ tables + `dbo.SearchFAQ` | ✅ |
| Microsoft Foundry `FAQ-Assistant-project` | ✅ |
| Microsoft Fabric workspace | manual (Exercise 5) |

> Secrets are never committed: `.env`, `.vm-cred`, and SQL-password diagnostic scripts are gitignored.
