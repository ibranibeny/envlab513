$s = @'
$m=[Environment]::GetEnvironmentVariable("Path","Machine")
if($m -notlike "*C:\Tools*"){ [Environment]::SetEnvironmentVariable("Path",$m+";C:\Tools","Machine") }
$c="C:\Program Files\Microsoft VS Code\bin\code.cmd"
$line="`"$c`" --install-extension ms-mssql.mssql --force & `"$c`" --install-extension github.copilot --force & `"$c`" --install-extension github.copilot-chat --force"
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name LabExt -Value "cmd /c $line"
$n=[Environment]::GetEnvironmentVariable("Path","Machine")
"tools="+($n -like "*C:\Tools*")+"; run=set"
'@
$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts $s -o json | ConvertFrom-Json
$r.value[0].message
