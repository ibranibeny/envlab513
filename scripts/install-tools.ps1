$ErrorActionPreference = 'Stop'
Invoke-WebRequest 'https://update.code.visualstudio.com/latest/win32-x64/stable' -OutFile "$env:TEMP\vscode.exe"
Start-Process "$env:TEMP\vscode.exe" -ArgumentList '/VERYSILENT','/MERGETASKS=!runcode,addtopath' -Wait
Invoke-WebRequest 'https://aka.ms/installazurecliwindows' -OutFile "$env:TEMP\azcli.msi"
Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\azcli.msi`" /qn" -Wait
'installed' | Out-File C:\lab513-bootstrap.txt
