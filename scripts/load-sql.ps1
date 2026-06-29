# =====================================================================
# LAB513 Exercise-00 - load FAQ tables (schema, seed, search proc) from your PC
#   Windows host (not WSL) so GSA does not block 1433. Reads ../.env.
#   Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File load-sql.ps1
# =====================================================================
$ErrorActionPreference='Stop'
$root='C:\Users\benyibrani\OneDrive - Microsoft\Documents\Workshop\Build26-Lab513\lab513'
$env=Get-Content "$root\.env" | % {$k,$v=$_ -split '=',2; if($k){Set-Variable $k $v}}
$srv=$SQL_FQDN; $db=$SQL_DB; $u=$SQL_ADMIN; $p=$SQL_PASSWORD
$exe="$env:TEMP\sqlcmd.exe"
if(-not(Test-Path $exe)){Invoke-WebRequest 'https://github.com/microsoft/go-sqlcmd/releases/download/v1.8.0/sqlcmd-windows-amd64.exe' -OutFile $exe}
foreach($f in '01_schema.sql','02_seed_faq.sql','04_search_proc.sql'){
  Write-Host "=== $f ==="
  & $exe -S $srv -d $db -U $u -P $p -i "$root\sql\$f"
}
Write-Host "=== verify ==="
& $exe -S $srv -d $db -U $u -P $p -Q "SELECT (SELECT COUNT(*) FROM dbo.FAQ_Content) AS faq, (SELECT COUNT(*) FROM sys.objects WHERE name='SearchFAQ') AS proc"
