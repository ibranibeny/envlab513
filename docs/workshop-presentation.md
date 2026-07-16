---
marp: true
theme: default
paginate: true
size: 16:9
header: 'LAB513 · Azure SQL Hyperscale + Microsoft Fabric + Microsoft Foundry'
footer: 'Microsoft Build 2026'
style: |
  section { font-family: 'Segoe UI', Arial, sans-serif; color: #243A5E; font-size: 26px; }
  h1 { color: #0078D4; }
  h2 { color: #243A5E; border-bottom: 3px solid #0078D4; padding-bottom: 6px; }
  section.lead { background: linear-gradient(135deg, #0078D4 0%, #243A5E 100%); color: #fff; text-align: center; justify-content: center; }
  section.lead h1 { color: #fff; font-size: 46px; }
  table { font-size: 21px; }
  th { background: #0078D4; color: #fff; }
  strong { color: #0078D4; }
  code { background: #F0F4F8; color: #D83B01; }
---

<!-- _class: lead -->

# LAB513
## Build an AI App with Azure SQL Hyperscale, Microsoft Fabric & Microsoft Foundry

**Retrieval-Augmented Generation (RAG) over enterprise FAQ data**

Microsoft Build 2026 · Hands-on Workshop

---

## Agenda

1. **Overview** — what you build & learning outcomes
2. **Architecture** — solution & technology stack
3. **RAG workflow** — end-to-end, step by step
4. **Exercises & security** — the 6 lab exercises + keyless auth
5. **Deploy & cost** — automation and runtime cost
6. **Next steps** — keep learning

> Speaker notes: ~45-minute hands-on lab. Exercises 00–04 verified; 05 is interactive in the Fabric portal.

---

## Overview & Architecture

Build an **AI-powered FAQ assistant** — grounded, governed, analytics-ready.

| Layer | Service | Role |
|-------|---------|------|
| **Data** | Azure SQL Hyperscale | Serverless Gen5 2-vCore, vector search |
| **AI** | Azure OpenAI (Foundry) | `gpt-5` + `text-embedding-3-small` |
| **Analytics** | Microsoft Fabric (F2) | OneLake mirroring + Power BI |
| **Governance** | Microsoft Purview | Catalog & lineage |
| **Orchestration** | Foundry Agents + MCP | SQL as a callable tool |

---

## End-to-End RAG Workflow

```mermaid
flowchart LR
    DEV["Developer<br/>VS Code + Copilot"] -->|1 T-SQL| SQL[("Azure SQL<br/>Hyperscale")]
    SQL -->|2 embeddings MI| EMB["text-embedding-3-small"]
    SQL -->|3 grounded prompt| GPT["gpt-5"]
    SQL -->|4 mirroring| OL["Fabric OneLake"]
    OL -->|5 Direct Lake| PBI["Power BI"]
    classDef d fill:#107C10,stroke:#0B520B,color:#fff;
    classDef a fill:#D83B01,stroke:#8A2600,color:#fff;
    classDef f fill:#5C2D91,stroke:#3B1D5E,color:#fff;
    class SQL d
    class EMB,GPT a
    class OL,PBI f
```

**Ingest → Embed → Retrieve → Augment → Generate → Analyze**

---

## Exercises & Security

| # | Exercise | Status |
|---|----------|--------|
| 00–01 | Readiness · Schema + embeddings + `SearchFAQ` | ✅ |
| 02–03 | Copilot semantic search · RAG → `gpt-5` | ✅ |
| 04 | Foundry agent + local MCP server | ✅ |
| 05 | Microsoft Fabric (OneLake + Power BI) | 🟡 Interactive |

**Keyless by design:** `disableLocalAuth=true` — SQL → Azure OpenAI via **Managed Identity**, no keys stored.

---

## Deploy, Cost & Next Steps

- **Automation** — `deploy.sh` provisions SQL, Foundry + models, Fabric; `teardown.sh` controls cost
- **Cost (per hour):** VM $0.200 · SQL Hyperscale $0.6849/vCore · Fabric F2 $0.38 · gpt-5 per-token
- **Tip:** run `deploy.sh --no-fabric` or `teardown.sh` to stop Fabric billing

```bash
./scripts/deploy.sh --instance <ID> --ai-location eastus2
```

**Keep learning:** aka.ms/build26-next-steps · Connect the **Microsoft Learn MCP Server** in VS Code

> Thank you!
