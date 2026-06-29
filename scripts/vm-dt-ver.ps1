$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts "(Test-Path 'C:\Tools\devtunnel.exe'); (& 'C:\Tools\devtunnel.exe' --version)" -o json | ConvertFrom-Json
$r.value[0].message
