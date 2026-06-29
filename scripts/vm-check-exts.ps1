$s = @'
$dt = Test-Path 'C:\Tools\devtunnel.exe'
$code='C:\Program Files\Microsoft VS Code\bin\code.cmd'
$list = if(Test-Path $code){ (& $code --list-extensions) -join ',' } else { 'no-code' }
'dt='+$dt+'; exts='+$list
'@
$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts $s -o json | ConvertFrom-Json
$r.value[0].message
