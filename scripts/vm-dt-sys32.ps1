$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts "Copy-Item C:\Tools\devtunnel.exe C:\Windows\System32\devtunnel.exe -Force; 'sys32='+(Test-Path C:\Windows\System32\devtunnel.exe)" -o json | ConvertFrom-Json
$r.value[0].message
