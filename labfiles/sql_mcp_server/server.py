"""
LAB513 - SQL MCP Server (Exercise 4: Foundry Agents)
====================================================
Exposes the Azure SQL `dbo.SearchFAQ` semantic-search stored procedure as an
MCP tool so a Microsoft Foundry agent (faq-orchestrator-agent) can ground its
answers on the FAQ knowledge base stored in Azure SQL Hyperscale.

Transport : Streamable HTTP  ->  http://0.0.0.0:8000/mcp
Expose it to Foundry with devtunnel (see ../../TASKS.md, Exercise 4):
    devtunnel create my-faq-tunnel<LAB_INSTANCE_ID> --allow-anonymous
    devtunnel port create my-faq-tunnel<LAB_INSTANCE_ID> -p 8000
    devtunnel host my-faq-tunnel<LAB_INSTANCE_ID>

Prerequisites
-------------
1. Python 3.10+  and  pip install -r requirements.txt
2. Microsoft ODBC Driver 18 for SQL Server (required by pyodbc):
     Windows : https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server
     WSL/Linux (Debian/Ubuntu):
         curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
         curl https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list
         sudo apt-get update && sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18
3. Connection settings via environment variables (copy .env.example -> .env).
   The deploy.sh script writes the matching values to lab513/.env.

Run
---
    python server.py
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import pyodbc
from mcp.server.fastmcp import FastMCP

# Load a sibling .env file if python-dotenv is installed (optional convenience).
try:
    from dotenv import load_dotenv

    load_dotenv(Path(__file__).with_name(".env"))
except ImportError:  # python-dotenv is optional
    pass

# ---------------------------------------------------------------------------
# Connection configuration (from environment / .env)
# ---------------------------------------------------------------------------
SQL_FQDN = os.environ.get("SQL_FQDN", "")
SQL_DB = os.environ.get("SQL_DB", "faq-ai-assistant-db")
SQL_USER = os.environ.get("SQL_ADMIN", "")
SQL_PASSWORD = os.environ.get("SQL_PASSWORD", "")
ODBC_DRIVER = os.environ.get("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")

CONN_STR = (
    f"Driver={{{ODBC_DRIVER}}};"
    f"Server=tcp:{SQL_FQDN},1433;"
    f"Database={SQL_DB};"
    f"Uid={SQL_USER};"
    f"Pwd={SQL_PASSWORD};"
    "Encrypt=yes;TrustServerCertificate=yes;Connection Timeout=30;"
)

mcp = FastMCP("faq-sql-mcp", host="0.0.0.0", port=8000)


@mcp.tool()
def search_faq(question: str) -> list[dict[str, Any]]:
    """Search the FAQ knowledge base using semantic vector search in Azure SQL.

    Calls the `dbo.SearchFAQ` stored procedure, which embeds the question with
    Azure OpenAI (text-embedding-3-small) and ranks FAQ entries by
    VECTOR_DISTANCE, returning the top matching rows as grounding context.

    The procedure takes a single `@user_question` parameter and returns the
    columns faq_id, category, question, answer (the same shape Exercise 3
    inserts into its #searchResults table).

    Args:
        question: The user's natural-language question.

    Returns:
        A list of matching FAQ rows (faq_id, category, question, answer).
        Empty list if the question is blank.
    """
    if not question or not question.strip():
        return []

    with pyodbc.connect(CONN_STR, timeout=30) as conn:
        cursor = conn.cursor()
        cursor.execute("EXEC dbo.SearchFAQ @user_question = ?", question)
        columns = [col[0] for col in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]


if __name__ == "__main__":
    if not SQL_FQDN or not SQL_USER:
        raise SystemExit(
            "Missing SQL connection settings. Copy .env.example to .env and fill "
            "in SQL_FQDN / SQL_ADMIN / SQL_PASSWORD (see lab513/.env from deploy.sh)."
        )
    # Banner matches the expected startup output shown in Exercise 4.
    print("[MCP] Starting FAQ SQL Assistant on http://0.0.0.0:8000")
    print("[MCP] MCP endpoint : http://0.0.0.0:8000/mcp")
    # Streamable HTTP transport serves the MCP endpoint at /mcp on host:port.
    mcp.run(transport="streamable-http")
