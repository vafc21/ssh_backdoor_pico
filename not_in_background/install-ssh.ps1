<# install-ssh.ps1 — installs OpenSSH Client/Server, enables sshd, adds firewall, prints status #>

# Self-elevate if needed
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  if ($PSCommandPath) {
    Start-Process -Verb RunAs -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
  } else { throw "Run this script from a file." }
}

$ErrorActionPreference = "Stop"
$capClient = "OpenSSH.Client~~~~0.0.1.0"
$capServer = "OpenSSH.Server~~~~0.0.1.0"

function Ensure-Capability {
  param([string]$Name)
  $cap = Get-WindowsCapability -Online -Name $Name
  if ($cap.State -ne "Installed") {
    Write-Host "[>] Installing $Name ..."
    Add-WindowsCapability -Online -Name $Name | Out-Null
    Write-Host "[+] Installed $Name."
  } else { Write-Host "[=] $Name already installed." }
}

function Ensure-Service {
  param([string]$Name)
  try {
    Set-Service -Name $Name -StartupType Automatic
    try { Start-Service -Name $Name } catch {}
    $svc = Get-Service -Name $Name
    Write-Host "[+] Service $($svc.Name): $($svc.Status) / $($svc.StartType)"
  } catch { Write-Host "[!] Service $Name not found." }
}

Write-Host "`n=== Installing OpenSSH (if needed) ==="
Ensure-Capability $capClient
Ensure-Capability $capServer

Write-Host "`n=== Ensuring services are running ==="
Ensure-Service "sshd"
# Optional: uncomment if you want key agent always on
# Ensure-Service "ssh-agent"

Write-Host "`n=== Firewall rule ==="
$fwDisplay = "OpenSSH Server (sshd)"; $fwName = "OpenSSH-Server-In-TCP"
$rule = Get-NetFirewallRule -DisplayName $fwDisplay -ErrorAction SilentlyContinue
if (-not $rule) { $rule = Get-NetFirewallRule -Name $fwName -ErrorAction SilentlyContinue }
if ($rule) {
  Enable-NetFirewallRule -Name $rule.Name | Out-Null
  Write-Host "[=] Firewall rule present."
} else {
  New-NetFirewallRule -Name $fwName -DisplayName $fwDisplay -Enabled True -Direction Inbound -Profile Any -Action Allow -Protocol TCP -LocalPort 22 | Out-Null
  Write-Host "[+] Firewall rule added."
}

Write-Host "`n=== Status ==="
try { ssh -V } catch { Write-Host "ssh client not on PATH (okay)." }
Get-Service sshd | Format-Table Name,Status,StartType -Auto
if (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue) {
  Write-Host "sshd is listening on port 22."
} else {
  Write-Host "Port 22 not listening yet; try: Restart-Service sshd"
}

$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.' } | Select-Object IPAddress
if ($ips) {
  $u=$env:USERNAME
  Write-Host "`nTry:"
  Write-Host "  ssh $u@localhost"
  $ips | ForEach-Object { "  ssh {0}@{1}" -f $u, $_.IPAddress | Write-Host }
}

Write-Host "`nDone." -ForegroundColor Green
