# LAB513 — Runbook (TASKS.md)

How to run **Build an AI app with Azure SQL Hyperscale, Microsoft Fabric, and
Microsoft Foundry** on **your own** Azure subscription, in **Indonesia Central**
(AI services fall back to **Southeast Asia** — see [REPORT.md](REPORT.md) §2).

Read [REPORT.md](REPORT.md) first for the honest region/cost/security picture.

---

## Task 0 — Fix prerequisites (do this before anything)

### 0.1 Fix WSL networking (you currently cannot reach Azure from WSL)
Pick ONE (details in [REPORT.md](REPORT.md) §7):
```bash
# Quick DNS fix inside WSL:
echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf
# Verify:
curl -fsS -o /dev/null -w '%{http_code}\n' https://management.azure.com/   # expect 401/200, NOT a network error
```
If that doesn't stick, enable mirrored networking in `C:\Users\benyibrani\.wslconfig`:
```ini
[wsl2]
networkingMode=mirrored
```
then in PowerShell: `wsl --shutdown`, reopen WSL.
**Alternative:** run everything from [Azure Cloud Shell](https://shell.azure.com) (bash) — upload the `lab513/` folder.

### 0.2 Tools (Exercise 00)
| Tool | Check | Needed for |
|---|---|---|
| Azure CLI | `az version` | deploy/teardown |
| `sqlcmd` (go-sqlcmd) | `sqlcmd -?` | SQL bootstrap |
| Python 3 + pip | `python3 --version && pip --version` | Exercise 4 |
| .NET SDK | `dotnet --version` | Exercise 6 |
| devtunnel | `devtunnel --version` | Exercise 4 |
| VS Code + SQL Server ext + GitHub Copilot | — | Exercises 1,2,6 |
| ODBC Driver 18 for SQL Server | — | Exercise 4 (`pyodbc`) |

Sign in:
```bash
az login                      # or: az login --use-device-code
az account set --subscription "ME-MngEnvMCAP708029-benyibrani-1"
az account show -o table
```

### 0.3 Lab folders (Exercise 00, Task 3)
Source of truth lives in the repo under `lab513/labfiles/` (version-controlled):
- `lab513/labfiles/sql_mcp_server/` → `server.py`, `requirements.txt`, `.env.example`
- `lab513/labfiles/sql-mcp-lab/` → `dab-config.json`, `.vscode/mcp.json`

`deploy.sh` stages them to the Windows paths the lab expects (default
`/mnt/c/LabFiles` = `C:\LabFiles`), so after Task 1 you get:
- `C:\LabFiles\sql_mcp_server\` → `server.py`, `requirements.txt`, `.env.example`
- `C:\LabFiles\sql-mcp-lab\` → `dab-config.json`, `.vscode\mcp.json`

Override the target with `--lab-files-dir DIR`, or skip staging with
`--no-lab-files` and copy manually: `cp -R lab513/labfiles/* <your C:\LabFiles path>`.

---

## Task 1 — Deploy Azure resources (Azure CLI)

From the repo root in WSL/bash:
```bash
cd "lab513/scripts"
chmod +x deploy.sh teardown.sh
./deploy.sh                       # generates a random LAB_INSTANCE_ID
# or pin an id and auto-confirm:
# ./deploy.sh --instance demo01 --yes
# skip Fabric (saves the most money):  ./deploy.sh --no-fabric
```
The script will:
1. Preflight network + Azure login.
2. Validate SQL Hyperscale in Indonesia Central, pick an AI region with `gpt-4o` + `text-embedding-3-small`, check Fabric.
3. Show a plan and ask you to type `yes`.
4. Create RG, VNet/Subnet, **open NSG**, SQL server + **open firewall** + Hyperscale DB, AI Foundry + 2 model deployments, Fabric F2.
5. Write secrets to `lab513/.env` (chmod 600).
6. If `sqlcmd` is present, run the SQL bootstrap (schema → seed → `SearchFAQ` → embeddings).
7. Stage `lab513/labfiles/` to `C:\LabFiles\` (`sql_mcp_server`, `sql-mcp-lab`) for Exercises 4 & 6.

**Outputs to keep:** `cat lab513/.env` — has `SQL_FQDN`, `SQL_ADMIN`, `SQL_PASSWORD`, `AI_ENDPOINT`, `AI_KEY`, deployment names.

> If `sqlcmd` was missing, install go-sqlcmd and re-run just the bootstrap:
> ```bash
> # re-applies 01→04 using the rendered files in lab513/.generated
> source ../.env
> sqlcmd -S "tcp:${SQL_FQDN},1433" -d "$SQL_DB" -U "$SQL_ADMIN" -P "$SQL_PASSWORD" -C -i ../sql/01_schema.sql
> sqlcmd -S "tcp:${SQL_FQDN},1433" -d "$SQL_DB" -U "$SQL_ADMIN" -P "$SQL_PASSWORD" -C -i ../sql/02_seed_faq.sql
> sqlcmd -S "tcp:${SQL_FQDN},1433" -d "$SQL_DB" -U "$SQL_ADMIN" -P "$SQL_PASSWORD" -C -i ../.generated/04_search_proc.sql
> sqlcmd -S "tcp:${SQL_FQDN},1433" -d "$SQL_DB" -U "$SQL_ADMIN" -P "$SQL_PASSWORD" -C -i ../.generated/03_generate_embeddings.sql
> ```

---

## Exercise 1 — AI-enhanced querying (VS Code + SQL)

1. VS Code → SQL Server extension → **Add Connection**:
   - Server: `faq-ai-assistant-{id}.database.windows.net` (from `.env` `SQL_FQDN`)
   - Database: `faq-ai-assistant-db`
   - Auth: **SQL Login** (`admin-{id}` + password from `.env`). *(The hosted lab uses Entra MFA; on your own subscription SQL auth is simplest.)*
2. Explore + validate:
   ```sql
   SELECT TOP 10 * FROM dbo.FAQ_Content;
   SELECT TOP 5  * FROM dbo.FAQ_Embeddings;
   SELECT COUNT(*) AS faq_count       FROM dbo.FAQ_Content;
   SELECT COUNT(*) AS embedding_count FROM dbo.FAQ_Embeddings;   -- must match faq_count
   ```
3. Semantic search:
   ```sql
   EXEC dbo.SearchFAQ @user_question = N'My product arrived damaged';
   EXEC dbo.SearchFAQ @user_question = N'Where can I check my delivery status?';
   ```
4. Keyword vs semantic (Task 6) — keyword returns **0 rows**, semantic still finds "How do I track my order?":
   ```sql
   SELECT TOP 3 c.faq_id, c.category, c.question, c.answer
   FROM dbo.FAQ_Content AS c
   WHERE c.question LIKE N'%delivery status%';            -- 0 rows (by design)
   EXEC dbo.SearchFAQ @user_question = N'Where can I check my delivery status?';
   ```

---

## Exercise 2 — Accelerate SQL with GitHub Copilot

1. Sign in to GitHub Copilot in VS Code (enterprise SSO if your tenant requires it).
2. In Copilot Chat:
   ```text
   Generate a T-SQL query for Azure SQL that returns the top 3 FAQ items most
   relevant to a customer question by using dbo.FAQ_Content and dbo.FAQ_Embeddings.
   ```
3. Check the generated SQL includes: `dbo.FAQ_Content`, `dbo.FAQ_Embeddings`, join on `faq_id`, `TOP 3`, `VECTOR_DISTANCE`.
   - **Watch the argument order:** Azure SQL expects the **metric first** → `VECTOR_DISTANCE('cosine', @v1, @v2)`. Keep the lab's validated query (`sql/04_search_proc.sql`) as the final version.
4. Optional Copilot prompts: explain the query, improve readability, suggest schema improvements, draft `dbo.usp_GetTopFaqMatches` (no need to deploy it).

---

## Exercise 3 — RAG with GPT-4o from inside SQL

> Needs `sp_invoke_external_rest_endpoint` (external REST from Azure SQL). The
> `@url`/`api-key` for the **chat** endpoint are in `.env` (`CHAT_URL`, `AI_KEY`).

1. Build grounding context (full script in the lab; uses `dbo.SearchFAQ` + `STRING_AGG`):
   ```sql
   EXEC dbo.SearchFAQ @user_question = N'My product arrived damaged';
   ```
2. Send the grounded prompt to GPT-4o. Fill `@url` with `CHAT_URL` and the
   `api-key` header with `AI_KEY` from `.env`:
   ```sql
   DECLARE @headers NVARCHAR(MAX) = N'{"api-key": "<AI_KEY from .env>"}';
   -- ...build @payload (messages) as in the lab...
   EXEC sp_invoke_external_rest_endpoint
        @method='POST',
        @url=N'<CHAT_URL from .env>',
        @headers=@headers, @payload=@payload, @response=@response OUTPUT;
   SELECT JSON_VALUE(@response,'$.result.choices[0].message.content') AS ai_answer;
   ```
3. Try `N'How do I track my order?'` (grounded answer) and
   `N'Can I pay using cryptocurrency?'` (should answer "I do not know").

---

## Exercise 4 — Foundry agent + local MCP tool

1. Start the MCP server (runs on Windows per the lab; needs ODBC Driver 18):
   ```powershell
   cd C:\LabFiles\sql_mcp_server
   copy .env.example .env       # then edit .env with SQL_FQDN / SQL_ADMIN / SQL_PASSWORD from lab513\.env
   python -m venv .venv ; .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   python server.py             # expect: [MCP] ... http://0.0.0.0:8000/mcp
   ```
2. Expose it with devtunnel (new terminal):
   ```bash
   devtunnel user login
   devtunnel create my-faq-tunnel{id} --allow-anonymous
   devtunnel port create my-faq-tunnel{id} -p 8000 --protocol http
   devtunnel host my-faq-tunnel{id}        # copy the https://...devtunnels.ms URL
   ```
3. Open Foundry (`https://ai.azure.com`). **Self-host note:** `deploy.sh` provisions the AI Foundry *resource* (`aif-lab513-{id}`) but **not** a project — on first use create a project named `FAQ-Assistant-project` (New Foundry → **+ Create project**). Then in that project → **Build** → **Tools**:
   - Connect a tool → Custom → **Model Context Protocol (MCP)** → Create.
   - Name `faq{id}`, **Remote MCP Server endpoint** = your tunnel URL, Auth **Unauthenticated** → Connect.
   - **Use in an agent** → name `faq-orchestrator-agent` → Create and open playground.
   - Instructions: "You are a support FAQ assistant. Use the MCP tool to retrieve relevant FAQ content before answering… If the tool returns nothing relevant, say you do not know." → Save.
4. Test: `My product arrived damaged` → agent calls the tool, grounded answer.
   `Can I pay using cryptocurrency?` → grounded "I do not know."

> Keep `server.py` and `devtunnel host` running during this exercise. `Ctrl+C` both when done (before Exercise 6, which reuses the terminal).

---

## Exercise 5 — Fabric mirroring + Power BI (browser)

1. `https://app.fabric.microsoft.com` → **+ New workspace** → name `Workspace{id}` → Apply.
   *(Assign it to your `fab{id}` capacity, or use a Fabric Trial — see note below.)*
2. **+ New Item** → **Mirrored Azure SQL Database** → Azure SQL Database. Connection:
   - Server `faq-ai-assistant-{id}.database.windows.net`, DB `faq-ai-assistant-db`
   - Auth kind **Basic** (= SQL auth), Username `admin-{id}`, Password from `.env`, encrypted connection **Enabled**.
3. In **Choose data**, select **only `dbo.FAQ_Content`** (NOT `dbo.FAQ_Embeddings`) → Connect → Create mirrored database.
4. Verify in **Tables** (refresh), open **SQL analytics endpoint** → `SELECT TOP 10 * FROM FAQ_Content;`.
5. **Create semantic model** `FAQ_Content`, storage mode **Direct Lake on SQL**, table `FAQ_Content` → Confirm.
6. Semantic model → **Create report** → Copilot prompts "What's in my data?", "FAQ count by category" → Save as `FAQ_rpt`.
7. Workspace → **Lineage view**: SQL DB → Mirrored DB → SQL analytics endpoint / Semantic model → Power BI report.

> **Fabric capacity note:** F2 bills continuously. If you used `--no-fabric` or want
> to avoid cost, enable a **Microsoft Fabric Trial** on the workspace instead and
> skip the `fab{id}` capacity.

---

## Exercise 6 — Expose SQL via Data API Builder (DAB) MCP

1. Stop the Python server from Exercise 4 (`Ctrl+C`). The folder is already set up:
   ```powershell
   cd C:\LabFiles\sql-mcp-lab
   dotnet new tool-manifest        # if not already present
   dotnet tool install microsoft.dataapibuilder
   dotnet tool run dab --version   # must be 1.7 or later
   ```
2. Edit `dab-config.json` → in the `connection-string`, replace `{LAB_INSTANCE_ID}`
   and `{PASSWORD}` with your values from `.env` (`SQL_ADMIN` already encodes the id).
3. Start the MCP server:
   ```powershell
   dotnet tool run dab start --config dab-config.json   # expect: Server started successfully / MCP enabled
   ```
4. `.vscode\mcp.json` is already provided. In VS Code chat, add `mcp.json` as context, then:
   ```text
   What tools are available?
   By leveraging MCP tool - Find the number of database records in FAQ_Content
   Find FAQ entries related to damaged products.
   Show me the different categories that exist in the faqContent table.
   ```
   Allow the tool in session when prompted.

---

## Task 9 — Tear everything down (stop the billing)

```bash
cd "lab513/scripts"
./teardown.sh                 # reads lab513/.env, confirms, deletes RG + purges AI account
# or: ./teardown.sh --instance demo01 --yes
```
Also remove manually (cannot be scripted):
- Foundry **agent** `faq-orchestrator-agent` + **MCP tool** `faq{id}` in `FAQ-Assistant-project`
- Fabric **workspace** `Workspace{id}` (mirrored db, semantic model, `FAQ_rpt`)
- The devtunnel: `devtunnel delete my-faq-tunnel{id}`

Verify nothing is left:
```bash
az group show -n "rg-lab513-{id}" -o table        # should error: not found
az cognitiveservices account list-deleted -o table # AI account should not be listed
```

---

## Quick reference

| Thing | Value |
|---|---|
| Resource group | `rg-lab513-{id}` |
| SQL FQDN | `faq-ai-assistant-{id}.database.windows.net` |
| Database | `faq-ai-assistant-db` |
| SQL admin | `admin-{id}` (password in `lab513/.env`) |
| AI endpoint / key | `.env` `AI_ENDPOINT` / `AI_KEY` |
| Chat / embed URL | `.env` `CHAT_URL` / `EMBED_URL` |
| Primary region | `indonesiacentral` |
| AI region | `southeastasia` (Azure OpenAI not in Indonesia Central) |
