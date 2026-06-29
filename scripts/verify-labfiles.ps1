$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts "'srv='+(Test-Path C:\LabFiles\sql_mcp_server\server.py); 'req='+(Test-Path C:\LabFiles\sql_mcp_server\requirements.txt); 'dab='+(Test-Path C:\LabFiles\sql-mcp-lab\dab-config.json); 'mcp='+(Test-Path C:\LabFiles\sql-mcp-lab\.vscode\mcp.json)" -o json | ConvertFrom-Json
$r.value[0].message
