$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts "'tools='+([Environment]::GetEnvironmentVariable('Path','Machine') -like '*Tools*')" -o json | ConvertFrom-Json
$r.value[0].message
