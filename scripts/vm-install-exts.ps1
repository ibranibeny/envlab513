$s = @'
$dt = Test-Path 'C:\Tools\devtunnel.exe'
$dtv = if($dt){ & 'C:\Tools\devtunnel.exe' --version } else { 'missing' }
$code='C:\Program Files\Microsoft VS Code\bin\code.cmd'
$exts=@()
if(Test-Path $code){ foreach($e in 'ms-mssql.mssql','github.copilot','github.copilot-chat'){ & $code --install-extension $e --force | Out-Null; $exts+=$e }; $list=(& $code --list-extensions) -join ',' }
'dt='+$dt+'; dtver='+$dtv+'; exts='+$list
'@
$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts $s -o json | ConvertFrom-Json
$r.value[0].message
