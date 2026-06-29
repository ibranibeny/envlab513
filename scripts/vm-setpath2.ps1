$s = @'
try{
  $m=[Environment]::GetEnvironmentVariable("Path","Machine")
  if($m -notlike "*C:\Tools*"){ [Environment]::SetEnvironmentVariable("Path",($m.TrimEnd(";")+";C:\Tools"),"Machine") }
  $n=[Environment]::GetEnvironmentVariable("Path","Machine")
  "ok tools="+($n -like "*C:\Tools*")
}catch{ "ERR "+$_.Exception.Message }
'@
$r=az vm run-command invoke -g rg-lab513-vm -n lab513vm --command-id RunPowerShellScript --scripts $s -o json | ConvertFrom-Json
$r.value[0].message
