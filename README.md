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
| `sql/05_external_model.sql` | EXTERNAL MODEL for `AI_GENERATE_EMBEDDINGS` (Exercise 2) — token/MI |
| `sql/06_rag_chat.sql` | Exercise 3 (RAG): grounded prompt → GPT-4o — **token/MI, run manually** |
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

## Exercise 2 & 3 — token auth instead of api-key (workshop note)

This environment's AI account has **local (key) auth disabled** (`disableLocalAuth=true`), so every official lab step that uses an **api-key** must be changed to a **token (Managed Identity)** call. The audience should know the difference:

| Lab step | Official (api-key) | This repo (token / Managed Identity) |
|---|---|---|
| Embeddings / `AI_GENERATE_EMBEDDINGS` | api-key in DSC `SECRET` | DSC `IDENTITY='Managed Identity', SECRET='{"resourceid":"https://cognitiveservices.azure.com"}'` + `CREATE EXTERNAL MODEL` — `sql/05_external_model.sql` |
| Exercise 3 RAG → GPT-4o | `@headers = N'{"api-key":"<KEY>"}'` | `@credential = [https://<ai-account>.cognitiveservices.azure.com]` (no key) — `sql/06_rag_chat.sql` |

**Exercise 3 (RAG) — run manually** in the mssql extension or portal Query editor. The key change in the `sp_invoke_external_rest_endpoint` call:

```sql
EXEC sp_invoke_external_rest_endpoint
    @method     = 'POST',
    @url        = N'https://<ai-account>.cognitiveservices.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21',
    @headers    = N'{"Content-Type":"application/json"}',   -- NO api-key here
    @credential = [https://<ai-account>.cognitiveservices.azure.com],  -- TOKEN (Managed Identity)
    @payload    = @payload,
    @response   = @response OUTPUT;
```

Full script (Task 1 + Task 2) is in `sql/06_rag_chat.sql`; `deploy.sh` renders a ready-to-run copy to `.generated/06_rag_chat.sql` with your account URL filled in.

### Before → after (the exact official snippet)

The official lab Task 2 snippet (api-key, empty `@url`):

```sql
DECLARE @headers NVARCHAR(MAX) = N'{"api-key": ""}';
EXEC sp_invoke_external_rest_endpoint
    @method  = 'POST',
    @url     = N'',
    @headers = @headers,
    @payload = @payload,
    @response = @response OUTPUT;
```

Becomes this **token** version — concrete values for the **current deployment** (`aif-lab513-2139d8`):

```sql
DECLARE @headers NVARCHAR(MAX) = N'{"Content-Type":"application/json"}';   -- no api-key
EXEC sp_invoke_external_rest_endpoint
    @method     = 'POST',
    @url        = N'https://aif-lab513-2139d8.cognitiveservices.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21',
    @headers    = @headers,
    @credential = [https://aif-lab513-2139d8.cognitiveservices.azure.com],   -- TOKEN (Managed Identity)
    @payload    = @payload,
    @response   = @response OUTPUT;
```

> Replace `aif-lab513-2139d8` with your own AI account name if you redeploy — the
> credential name must equal the account URL **without** a trailing slash, and it
> must already exist as a Managed-Identity DATABASE SCOPED CREDENTIAL (created by
> `03_generate_embeddings.sql`).

Prerequisites (created by the SQL bootstrap): `dbo.SearchFAQ`, the master key, the Managed-Identity **DATABASE SCOPED CREDENTIAL**, and the **Cognitive Services OpenAI User** role on the SQL server's managed identity.

### Complete runnable script — Exercise 3 Task 2 (token auth)

Run the **whole** block in one execution (Task 1 builds `@prompt`, Task 2 uses it). In the mssql extension, click in the editor with **no selection** and press **Ctrl+Shift+E** (or **Ctrl+A** then Run) — do **not** run only the Task 2 part or you get `Msg 137: Must declare the scalar variable "@prompt"`. Do **not** add `GO` between the tasks.

```sql
DECLARE @user_question NVARCHAR(1000) = N'My product arrived damaged';
DECLARE @context NVARCHAR(MAX);
DECLARE @prompt NVARCHAR(MAX);

CREATE TABLE #searchResults (
    faq_id INT,
    category NVARCHAR(200),
    question NVARCHAR(MAX),
    answer NVARCHAR(MAX)
);

INSERT INTO #searchResults (faq_id, category, question, answer)
EXEC dbo.SearchFAQ @user_question = @user_question;

SELECT @context =
(
    SELECT STRING_AGG(
        CONCAT(
            'Question: ', question, CHAR(10),
            'Answer: ', answer
        ),
        CHAR(10) + CHAR(10)
    )
    FROM #searchResults
);

SET @prompt =
N'Use ONLY the context below to answer the question.
Context:
' + ISNULL(@context, N'No relevant FAQ context found.') + N'
Question:
' + @user_question + N'
If the answer is not in the context, say you do not know.';

SELECT @prompt AS grounded_prompt;

DROP TABLE #searchResults;

DECLARE @payload  NVARCHAR(MAX);
DECLARE @response NVARCHAR(MAX);
-- TIDAK ada api-key lagi; token diambil dari @credential di bawah
DECLARE @headers  NVARCHAR(MAX) = N'{"Content-Type":"application/json"}';

SET @payload = N'{' +
N'"messages":[' +
N'{"role":"system","content":"You are a helpful assistant that answers questions by using only approved FAQ context."},' +
N'{"role":"user","content":"' + STRING_ESCAPE(@prompt, 'json') + N'"}' +
N'],' +
N'"temperature":0' +
N'}';

EXEC sp_invoke_external_rest_endpoint
    @method     = 'POST',
    @url        = N'https://aif-lab513-2139d8.cognitiveservices.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2024-10-21',
    @headers    = @headers,
    @credential = [https://aif-lab513-2139d8.cognitiveservices.azure.com],   -- TOKEN, bukan api-key
    @payload    = @payload,
    @response   = @response OUTPUT;

SELECT
    @response AS raw_response,
    COALESCE(
        JSON_VALUE(@response, '$.result.choices[0].message.content'),
        JSON_VALUE(@response, '$.choices[0].message.content'),
        JSON_VALUE(@response, '$.output[0].content[0].text'),
        @response
    ) AS ai_answer;
```

Try other questions by changing `@user_question` — e.g. `N'How do I track my order?'` or `N'Can I pay using cryptocurrency?'` (the latter should answer *I do not know*, demonstrating RAG grounding).
