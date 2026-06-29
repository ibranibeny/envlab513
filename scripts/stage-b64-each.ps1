# Stage labfiles to VM C:\LabFiles via base64, one invoke per file
$rg='rg-lab513-vm'; $vm='lab513vm'
$root='C:\Users\benyibrani\OneDrive - Microsoft\Documents\Workshop\Build26-Lab513\lab513\labfiles'
$files=@(
 @{src='sql_mcp_server\server.py'; dst='C:\LabFiles\sql_mcp_server\server.py'},
 @{src='sql_mcp_server\requirements.txt'; dst='C:\LabFiles\sql_mcp_server\requirements.txt'},
 @{src='sql-mcp-lab\dab-config.json'; dst='C:\LabFiles\sql-mcp-lab\dab-config.json'},
 @{src='sql-mcp-lab\.vscode\mcp.json'; dst='C:\LabFiles\sql-mcp-lab\.vscode\mcp.json'}
)
foreach($f in $files){
  $p=Join-Path $root $f.src; if(-not(Test-Path $p)){ Write-Host "skip $($f.src)"; continue }
  $b=[Convert]::ToBase64String([IO.File]::ReadAllBytes($p))
  $dir=Split-Path $f.dst
  $s="New-Item -ItemType Directory -Force '$dir'|Out-Null; [IO.File]::WriteAllBytes('$($f.dst)',[Convert]::FromBase64String('$b')); Test-Path '$($f.dst)'"
  $r=az vm run-command invoke -g $rg -n $vm --command-id RunPowerShellScript --scripts $s -o json | ConvertFrom-Json
  Write-Host ($f.dst + " -> " + $r.value[0].message)
}
