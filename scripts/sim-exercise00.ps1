# =====================================================================
# LAB513 - Exercise-00 simulation (run ON the VM, e.g. inside Bastion)
#   1. ensure git, 2. clone lab repo, 3. stage labfiles, 4. az login,
#   5. verify toolchain. Mirrors Build26-LAB513 environment setup.
# =====================================================================
$ErrorActionPreference = 'Continue'
$repo = if ($env:LAB_REPO) { $env:LAB_REPO } else { 'https://github.com/ibranibeny/envlab513.git' }
$work = 'C:\Lab'
$paths = @('C:\Program Files\Git\cmd','C:\Program Files\Microsoft VS Code\bin','C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin')
$env:Path = ($paths -join ';') + ';' + $env:Path

Write-Host '=== 1/5 ensure git ==='
if (-not (Get-Command git -EA SilentlyContinue)) { winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements }

Write-Host '=== 2/5 clone lab repo ==='
New-Item -ItemType Directory -Force -Path $work | Out-Null
if (Test-Path "$work\envlab513") { git -C "$work\envlab513" pull } else { git clone $repo "$work\envlab513" }

Write-Host '=== 3/5 stage labfiles ==='
$src = "$work\envlab513\labfiles"
if (Test-Path $src) { New-Item -ItemType Directory -Force -Path C:\LabFiles | Out-Null; Copy-Item "$src\*" C:\LabFiles -Recurse -Force }

Write-Host '=== 4/5 az login (device code) ==='
az login --use-device-code

Write-Host '=== 5/5 verify ==='
'git=' + (git --version)
'code=' + (& code --version)[0]
'az='  + ((az version | ConvertFrom-Json).'azure-cli')
'sub=' + (az account show --query name -o tsv)
'labfiles=' + ((Get-ChildItem C:\LabFiles -EA SilentlyContinue).Count) + ' items'
