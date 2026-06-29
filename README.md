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
