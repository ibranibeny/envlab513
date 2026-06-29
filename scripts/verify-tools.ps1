$c = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
$a = 'C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
'CODE=' + (& $c --version)[0]
'AZ=' + ((& $a version 2>&1 | Select-String 'azure-cli') -replace '\s+',' ').Trim()
'GIT=' + (git --version 2>&1)
