# install-ssh.ps1 — full setup: OpenSSH, firewall, sshadmin (random pw once), keys, robust logging
$ErrorActionPreference = 'SilentlyContinue'

# Resolve Pico root from this script's path
$P = [System.IO.Path]::GetPathRoot($PSCommandPath)  # e.g. 'D:\'
$logPath   = Join-Path $P 'pico_ips.txt'
$credsPath = Join-Path $P 'ssh_creds.txt'           # stores: sshadmin<TAB>password (if created)
$userPath  = Join-Path $P 'ssh_user.txt'
$passPath  = Join-Path $P 'ssh_pass.txt'

# --- 1) Ensure OpenSSH Server installed (GitHub ZIP) ---
$svc = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $svc) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $tmp  = Join-Path $env:TEMP 'openssh_install'
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  $zip  = Join-Path $tmp 'OpenSSH-Win64.zip'
  $dest = 'C:\Program Files\OpenSSH'

  $rel   = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest' -UseBasicParsing
  $asset = $rel.assets | Where-Object { $_.name -eq 'OpenSSH-Win64.zip' } | Select-Object -First 1
  Invoke-WebRequest $asset.browser_download_url -OutFile $zip
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  Expand-Archive -Path $zip -DestinationPath $dest -Force
  PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'install-sshd.ps1') | Out-Null
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 2) Start + enable sshd; firewall allow 22/TCP ---
Set-Service sshd -StartupType Automatic
Start-Service sshd
$fwName='OpenSSH-Server-In-TCP'; $fwDisp='OpenSSH Server (sshd)'
$rule = Get-NetFirewallRule -DisplayName $fwDisp -ErrorAction SilentlyContinue
if (-not $rule) { $rule = Get-NetFirewallRule -Name $fwName -ErrorAction SilentlyContinue }
if ($rule) { Enable-NetFirewallRule -Name $rule.Name | Out-Null }
else {
  New-NetFirewallRule -Name $fwName -DisplayName $fwDisp -Enabled True -Direction Inbound `
    -Profile Any -Action Allow -Protocol TCP -LocalPort 22 | Out-Null
}

# --- 3) Create/reuse local admin 'sshadmin' with a per-PC random password (only on first create) ---
$UserName = 'sshadmin'
$exists = [bool](Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)
$Password = $null
if (-not $exists) {
  $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#-_.'.ToCharArray()
  $Password = -join (Get-Random -InputObject $chars -Count 16)
  $sec = ConvertTo-SecureString $Password -AsPlainText -Force
  New-LocalUser -Name $UserName -Password $sec -FullName $UserName -PasswordNeverExpires:$true
  Add-LocalGroupMember -Group Administrators -Member $UserName -ErrorAction SilentlyContinue
  Enable-LocalUser -Name $UserName -ErrorAction SilentlyContinue

  # Persist credentials to Pico for later background logs
  "$UserName`t$Password" | Out-File -FilePath $credsPath -Encoding ascii -Force
  $UserName | Out-File -FilePath $userPath -Encoding ascii -Force
  $Password | Out-File -FilePath $passPath -Encoding ascii -Force
} else {
  Add-LocalGroupMember -Group Administrators -Member $UserName -ErrorAction SilentlyContinue
  Enable-LocalUser -Name $UserName -ErrorAction SilentlyContinue
}

# --- 4) Optional: append public key to administrators_authorized_keys if present on Pico ---
$pub = $null
if (Test-Path (Join-Path $P 'id_ed25519.pub')) { $pub = Join-Path $P 'id_ed25519.pub' }
elseif (Test-Path (Join-Path $P 'id_rsa.pub'))  { $pub = Join-Path $P 'id_rsa.pub'  }
elseif (Test-Path (Join-Path $P 'ssh_pubkey.txt')) { $pub = Join-Path $P 'ssh_pubkey.txt' }
if ($pub) {
  $admDir = 'C:\ProgramData\ssh'
  New-Item -ItemType Directory -Path $admDir -Force | Out-Null
  $dest = Join-Path $admDir 'administrators_authorized_keys'
  Get-Content $pub | Add-Content -Path $dest
  icacls $admDir /inheritance:r | Out-Null
  icacls $admDir /grant 'Administrators:F' 'SYSTEM:F' | Out-Null
  icacls $dest /inheritance:r | Out-Null
  icacls $dest /grant 'Administrators:F' 'SYSTEM:F' | Out-Null
}

# --- 5) Robust logging to pico_ips.txt (auto-create, retries) ---
$ts = Get-Date -Format o
$hn = $env:COMPUTERNAME
$ip = (Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null}).IPv4Address.IPAddress
if (-not $ip) {
  $ip = (Get-NetIPAddress -AddressFamily IPv4 |
         Where-Object { $_.IPAddress -notmatch '^127\.|^169\.254\.' } |
         Select-Object -ExpandProperty IPAddress -First 1)
}
if (-not (Test-Path $logPath)) { New-Item -ItemType File -Path $logPath -Force | Out-Null }

# Include creds if we just created them; else mark password "(unchanged)"
if ($Password) {
  $userOut = $UserName; $passOut = $Password
} else {
  $userOut = $UserName; $passOut = '(unchanged)'
}
$line = "$ts`t$hn`t$ip`t$userOut`t$passOut"

$ok=$false
for ($i=0; $i -lt 8 -and -not $ok; $i++) {
  try { $line | Out-File -FilePath $logPath -Append -Encoding ascii; $ok=$true }
  catch { Start-Sleep -Milliseconds 300 }
}
