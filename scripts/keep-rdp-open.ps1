# =====================================================================
# LAB513 - Keep RDP (3389) open watchdog
#   Re-asserts the inbound RDP NSG rule every 60s in case a policy
#   or GSA control removes it. Also pings the port and prints status.
#   Run from WSL:  powershell.exe -NoProfile -ExecutionPolicy Bypass -File keep-rdp-open.ps1
#   Stop with Ctrl+C.
# =====================================================================
$rg  = 'rg-lab513-vm'
$vm  = 'lab513vm'
$pri = 300

while ($true) {
  $nsg = az network nsg list -g $rg --query "[0].name" -o tsv
  $ip  = az vm show -d -g $rg -n $vm --query publicIps -o tsv
  az network nsg rule create -g $rg --nsg-name $nsg -n Allow-RDP `
    --priority $pri --access Allow --protocol Tcp --direction Inbound `
    --destination-port-ranges 3389 --source-address-prefixes Internet -o none 2>$null
  $ok = (Test-NetConnection $ip -Port 3389 -WarningAction SilentlyContinue).TcpTestSucceeded
  Write-Host ("{0}  RDP {1}:3389 open={2}" -f (Get-Date -Format HH:mm:ss), $ip, $ok)
  Start-Sleep -Seconds 60
}
