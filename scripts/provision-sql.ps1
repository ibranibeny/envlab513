# =====================================================================
# LAB513 Exercise-00 - provision Azure SQL Hyperscale with random LAB_INSTANCE_ID
#   server faq-ai-assistant-<id>, db faq-ai-assistant-db, admin admin-<id>
#   Run from WSL: powershell.exe -NoProfile -ExecutionPolicy Bypass -File provision-sql.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
$rg  = 'rg-lab513-vm'
$loc = 'indonesiacentral'
$id  = -join ((48..57)+(97..102) | Get-Random -Count 6 | % {[char]$_})  # 6 hex
$srv = "faq-ai-assistant-$id"
$db  = 'faq-ai-assistant-db'
$adm = "admin-$id"
$pwd = 'Aa1!' + ([guid]::NewGuid().ToString('N').Substring(0,18)) + 'Zz'
$env = "$PSScriptRoot\..\.env"

Write-Host "=== LAB_INSTANCE_ID=$id ==="
Write-Host "=== 1/3 SQL server ==="
az sql server create -g $rg -n $srv -l $loc -u $adm -p $pwd -o none
Write-Host "=== 2/3 firewall (lab-open) + Hyperscale db ==="
az sql server firewall-rule create -g $rg -s $srv -n all --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255 -o none
az sql db create -g $rg -s $srv -n $db -e Hyperscale -f Gen5 -c 2 --compute-model Serverless -o none
Write-Host "=== 3/3 write .env ==="
@"
LAB_INSTANCE_ID=$id
SQL_FQDN=$srv.database.windows.net
SQL_DB=$db
SQL_ADMIN=$adm
SQL_PASSWORD=$pwd
"@ | Out-File -Encoding ascii $env
Write-Host "SQL ready: $srv.database.windows.net / $db  admin=$adm  (creds in lab513/.env)"
