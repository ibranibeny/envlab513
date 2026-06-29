$ErrorActionPreference = 'Stop'

# VS Code
if(-not(Test-Path 'C:\Program Files\Microsoft VS Code\Code.exe')){
  Invoke-WebRequest 'https://update.code.visualstudio.com/latest/win32-x64/stable' -OutFile "$env:TEMP\vscode.exe"
  Start-Process "$env:TEMP\vscode.exe" -ArgumentList '/VERYSILENT','/MERGETASKS=!runcode,addtopath' -Wait
}

# Azure CLI
if(-not(Get-Command az -EA SilentlyContinue)){
  Invoke-WebRequest 'https://aka.ms/installazurecliwindows' -OutFile "$env:TEMP\azcli.msi"
  Start-Process msiexec.exe -ArgumentList "/i `"$env:TEMP\azcli.msi`" /qn" -Wait
}

# Git for Windows
if(-not(Get-Command git -EA SilentlyContinue)){
  Invoke-WebRequest 'https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.1/Git-2.47.0-64-bit.exe' -OutFile "$env:TEMP\git.exe"
  Start-Process "$env:TEMP\git.exe" -ArgumentList '/VERYSILENT','/NORESTART','/MERGETASKS=!runcode' -Wait
}

# Python 3.12 (sql_mcp_server + pip)
if(-not(Get-Command python -EA SilentlyContinue)){
  Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe' -OutFile "$env:TEMP\python.exe"
  Start-Process "$env:TEMP\python.exe" -ArgumentList '/quiet','InstallAllUsers=1','PrependPath=1','Include_pip=1' -Wait
}

# devtunnel (Exercise 4)
if(-not(Get-Command devtunnel -EA SilentlyContinue)){
  New-Item -ItemType Directory -Force 'C:\Tools' | Out-Null
  Invoke-WebRequest 'https://aka.ms/TunnelsCliDownload/win-x64' -OutFile 'C:\Tools\devtunnel.exe'
  $m=[Environment]::GetEnvironmentVariable('Path','Machine'); if($m -notlike '*C:\Tools*'){[Environment]::SetEnvironmentVariable('Path','C:\Tools;'+$m,'Machine')}
}

# VS Code extensions: SQL Server, GitHub Copilot, Copilot Chat (Exercise 1/2)
$code='C:\Program Files\Microsoft VS Code\bin\code.cmd'
if(Test-Path $code){
  foreach($ext in 'ms-mssql.mssql','github.copilot','github.copilot-chat'){
    & $code --install-extension $ext --force
  }
}

'installed' | Out-File C:\lab513-bootstrap.txt
