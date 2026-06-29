$s = @'
$m=[Environment]::GetEnvironmentVariable('Path','Machine')
$ro=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name InstallVSCodeExts -ea 0).InstallVSCodeExts
'tools='+($m -like '*C:\Tools*')+'; dtfile='+(Test-Path C:\Tools\devtunnel.exe)+'; runonce='+([bool]$ro)
'@
$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts $s -o json | ConvertFrom-Json
$r.value[0].message
