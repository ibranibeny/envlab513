$ErrorActionPreference='Stop'
if(-not(Get-Command git -EA SilentlyContinue)){Invoke-WebRequest 'https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.1/Git-2.47.0-64-bit.exe' -OutFile "$env:TEMP\git.exe"; Start-Process "$env:TEMP\git.exe" -Args '/VERYSILENT','/NORESTART' -Wait}
if(-not(Get-Command gh -EA SilentlyContinue)){Invoke-WebRequest 'https://github.com/cli/cli/releases/download/v2.62.0/gh_2.62.0_windows_amd64.msi' -OutFile "$env:TEMP\gh.msi"; Start-Process msiexec.exe -Args "/i `"$env:TEMP\gh.msi`" /qn" -Wait}
'git+gh installed'
