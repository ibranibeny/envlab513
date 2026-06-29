$out=@()
foreach($c in 'code','python','pip','dotnet','devtunnel'){ $p=(Get-Command $c -ErrorAction SilentlyContinue); $out+= "$c=$([bool]$p)" }
$out+= "LabFiles_sql_mcp_server=" + (Test-Path 'C:\LabFiles\sql_mcp_server')
$out+= "requirements.txt=" + (Test-Path 'C:\LabFiles\sql_mcp_server\requirements.txt')
$out+= "server.py=" + (Test-Path 'C:\LabFiles\sql_mcp_server\server.py')
$out+= "sql-mcp-lab=" + (Test-Path 'C:\LabFiles\sql-mcp-lab')
$out -join "`n"
