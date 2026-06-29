# =====================================================================
# LAB513 - Deploy Azure Bastion (browser RDP, bypasses laptop GSA)
#   Run from WSL: powershell.exe -NoProfile -ExecutionPolicy Bypass -File create-bastion.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
$rg = 'rg-lab513-vm'
$loc = 'indonesiacentral'
$bip = 'lab513-bastion-pip'
$bn  = 'lab513-bastion'

$vnet = az network vnet list -g $rg --query "[0].name" -o tsv
Write-Host "VNet=$vnet"

Write-Host "=== 1/3 AzureBastionSubnet ==="
az network vnet subnet create -g $rg --vnet-name $vnet -n AzureBastionSubnet --address-prefixes 10.0.1.0/26 -o none

Write-Host "=== 2/3 public IP ==="
az network public-ip create -g $rg -n $bip --sku Standard --location $loc -o none

Write-Host "=== 3/3 Bastion (Standard, ~10 min) ==="
az network bastion create -g $rg -n $bn --public-ip-address $bip --vnet-name $vnet --location $loc --sku Standard -o none
if ($LASTEXITCODE -ne 0) { throw "bastion create failed" }
Write-Host "Bastion ready. Connect: Portal > lab513vm > Connect > Bastion > user labadmin"
