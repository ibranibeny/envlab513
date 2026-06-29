$s = @'
$m=[Environment]::GetEnvironmentVariable('Path','Machine')
$hasTools = $m -like '*C:\Tools*'
if(-not $hasTools){ [Environment]::SetEnvironmentVariable('Path','C:\Tools;'+$m,'Machine') }
# Auto-install VS Code extensions at next interactive login (per-user)
$cmd='"C:\Program Files\Microsoft VS Code\bin\code.cmd" --install-extension ms-mssql.mssql --force & "C:\Program Files\Microsoft VS Code\bin\code.cmd" --install-extension github.copilot --force & "C:\Program Files\Microsoft VS Code\bin\code.cmd" --install-extension github.copilot-chat --force'
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'InstallVSCodeExts' -Value ("cmd /c "+$cmd) -PropertyType String -Force | Out-Null
'tools_path='+($m -like '*C:\Tools*' -or -not $hasTools)+'; runonce=set'
'@
$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts $s -o json | ConvertFrom-Json
$r.value[0].message
