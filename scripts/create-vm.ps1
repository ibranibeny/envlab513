# =====================================================================
# LAB513 - Create a standard lab VM in Indonesia Central
#   - Public IP, RDP (3389) open
#   - Installs VS Code (stable) + Azure CLI via run-command
#   - Admin account created here; sign in to az on the VM later
# Run from WSL via:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File create-vm.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'

$rg     = 'rg-lab513-vm'
$loc    = 'indonesiacentral'
$vm     = 'lab513vm'
$user   = 'labadmin'
$size   = 'Standard_D2s_v5'
$image  = 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest'
$rand   = -join ((48..57)+(97..122) | Get-Random -Count 5 | ForEach-Object {[char]$_})
$dns    = "lab513vm$rand"

# 24-char password meeting Windows complexity rules
$pwd = ('Aa1!' + ([guid]::NewGuid().ToString('N').Substring(0,18) + 'Zz'))
$credFile = Join-Path $PSScriptRoot '..\.vm-cred'

Write-Host "=== 1/4 resource group ==="
az group create -n $rg -l $loc -o none --tags project=lab513 purpose=lab-vm

Write-Host "=== 2/5 creating VM ($size, Win2022) ==="
az vm create -g $rg -n $vm -l $loc `
  --image $image --size $size `
  --admin-username $user --admin-password $pwd `
  --public-ip-sku Standard --public-ip-address-dns-name $dns `
  --nsg-rule RDP -o none
if ($LASTEXITCODE -ne 0) { throw "VM create failed" }

Write-Host "=== 3/5 ensuring inbound RDP (3389) ==="
$nsg = az network nsg list -g $rg --query "[0].name" -o tsv
az network nsg rule create -g $rg --nsg-name $nsg -n Allow-RDP `
  --priority 300 --access Allow --protocol Tcp --direction Inbound `
  --destination-port-ranges 3389 --source-address-prefixes Internet -o none 2>$null

$ip   = az vm show -d -g $rg -n $vm --query publicIps -o tsv
$fqdn = az network public-ip list -g $rg --query "[0].dnsSettings.fqdn" -o tsv

Write-Host "=== 4/5 installing VS Code + Azure CLI on the VM ==="
az vm run-command invoke -g $rg -n $vm --command-id RunPowerShellScript `
  --scripts "@$PSScriptRoot\install-tools.ps1" -o none

Write-Host "=== 5/5 done ==="
"VM=$vm RG=$rg LOC=$loc USER=$user PASSWORD=$pwd IP=$ip FQDN=$fqdn" | Out-File $credFile
Write-Host "RDP: $ip:3389  (or $fqdn)"
Write-Host "USER: $user"
Write-Host "PASS saved to: $credFile"
