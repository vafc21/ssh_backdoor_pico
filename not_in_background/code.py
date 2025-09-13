# code.py — Pico W HID: Windows SSH setup + per-PC random password (no indexing) + robust logging with retries
import time
import usb_hid
from adafruit_hid.keyboard import Keyboard
from adafruit_hid.keycode import Keycode
from adafruit_hid.keyboard_layout_us import KeyboardLayoutUS

ADMIN_USER = "sshadmin"          # separate local admin; your normal login is untouched
LOG_FILE   = "pico_ips.txt"      # written on the Pico drive

kbd = Keyboard(usb_hid.devices)
layout = KeyboardLayoutUS(kbd)

def sendline(s, delay=1.0):
    """Type a full line, press Enter, wait briefly."""
    layout.write(s)
    kbd.send(Keycode.ENTER)
    time.sleep(delay)

time.sleep(3)  # let Windows enumerate HID keyboard

# --- Launch elevated PowerShell (you must click UAC 'Yes')
kbd.send(Keycode.WINDOWS, Keycode.R); time.sleep(0.7)
layout.write("powershell"); time.sleep(0.3)
kbd.send(Keycode.CONTROL, Keycode.SHIFT, Keycode.ENTER); time.sleep(2.5)
# harmless nudge if focus is on 'No'
kbd.send(Keycode.LEFT_ARROW, Keycode.ENTER); time.sleep(2.0)

# A) Detect Pico drive ($P)
sendline("$ErrorActionPreference='SilentlyContinue'")
sendline("$pdrv = (Get-Volume | Where-Object FileSystemLabel -eq 'CIRCUITPY' | Select-Object -Expand DriveLetter -First 1)")
sendline("if (-not $pdrv) { $root = (Get-PSDrive -PSProvider FileSystem | "
        "Where-Object { Test-Path ($_.Root + 'code.py') } | Select-Object -Expand Root -First 1); "
        "if ($root) { $pdrv = $root.Substring(0,1) } }")
sendline("if ($pdrv) { $P = ($pdrv + ':') } else { $P = 'D:' }")
sendline("Write-Host ('[PicoDrive] ' + $P)")

# B) Ensure OpenSSH Server exists (install from GitHub if missing)
sendline("$svc = Get-Service sshd -ErrorAction SilentlyContinue")
sendline("if (-not $svc) { "
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; "
        "$tmp = Join-Path $env:TEMP 'openssh_install'; New-Item -ItemType Directory -Path $tmp -Force | Out-Null; "
        "$zip = Join-Path $tmp 'OpenSSH-Win64.zip'; "
        "$rel = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/Win32-OpenSSH/releases/latest' -UseBasicParsing; "
        "$asset = $rel.assets | Where-Object { $_.name -eq 'OpenSSH-Win64.zip' } | Select-Object -First 1; "
        "Invoke-WebRequest $asset.browser_download_url -OutFile $zip; "
        "$dest = 'C:\\Program Files\\OpenSSH'; New-Item -ItemType Directory -Path $dest -Force | Out-Null; "
        "Expand-Archive -Path $zip -DestinationPath $dest -Force; "
        "PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'install-sshd.ps1'); "
        "Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; "
        "}")

# C) Start + enable sshd; ensure firewall rule
sendline("Set-Service sshd -StartupType Automatic")
sendline("Start-Service sshd")
sendline("$fwDisplay='OpenSSH Server (sshd)'; $fwName='OpenSSH-Server-In-TCP'")
sendline("$rule = Get-NetFirewallRule -DisplayName $fwDisplay -ErrorAction SilentlyContinue")
sendline("if (-not $rule) { $rule = Get-NetFirewallRule -Name $fwName -ErrorAction SilentlyContinue }")
sendline("if ($rule) { Enable-NetFirewallRule -Name $rule.Name | Out-Null } else { "
        "New-NetFirewallRule -Name $fwName -DisplayName $fwDisplay -Enabled True -Direction Inbound "
        "-Profile Any -Action Allow -Protocol TCP -LocalPort 22 | Out-Null }")

# D) Create/reuse admin account with per-PC random password (no indexing syntax)
sendline("$u='" + ADMIN_USER + "'")
sendline("$exists = [bool](Get-LocalUser -Name $u -ErrorAction SilentlyContinue)")
sendline("$pw_note = ''")
sendline("$p = $null")
sendline("if (-not $exists) { "
        "$chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#-_.'; "
        "$charsArr = $chars.ToCharArray(); "
        "$len = 16; "
        "$p = -join (Get-Random -InputObject $charsArr -Count $len); "
        "$sec = ConvertTo-SecureString $p -AsPlainText -Force; "
        "New-LocalUser -Name $u -Password $sec -FullName $u -PasswordNeverExpires:$true; "
        "$pw_note = $p "
        "} else { "
        "$pw_note = '(unchanged)' "
        "}")
sendline("Enable-LocalUser -Name $u -ErrorAction SilentlyContinue")
sendline("Add-LocalGroupMember -Group 'Administrators' -Member $u -ErrorAction SilentlyContinue")

# E) Optional: add a public key from the Pico for key-based SSH
sendline("$pub = $null")
sendline("if (Test-Path ($P + '\\id_ed25519.pub')) { $pub = $P + '\\id_ed25519.pub' }")
sendline("elseif (Test-Path ($P + '\\id_rsa.pub')) { $pub = $P + '\\id_rsa.pub' }")
sendline("elseif (Test-Path ($P + '\\ssh_pubkey.txt')) { $pub = $P + '\\ssh_pubkey.txt' }")
sendline("if ($pub) { "
        "$admDir = 'C:\\ProgramData\\ssh'; New-Item -ItemType Directory -Path $admDir -Force | Out-Null; "
        "$dest = Join-Path $admDir 'administrators_authorized_keys'; "
        "Get-Content $pub | Add-Content -Path $dest; "
        "icacls $admDir /inheritance:r | Out-Null; icacls $admDir /grant 'Administrators:F' 'SYSTEM:F' | Out-Null; "
        "icacls $dest /inheritance:r | Out-Null; icacls $dest /grant 'Administrators:F' 'SYSTEM:F' | Out-Null; "
        "Write-Host ('[keys] Appended public key from ' + $pub) "
        "} else { Write-Host '[keys] No public key found on Pico' }")

# F) ALWAYS recreate/append the log on the Pico (robust + retries)
# Re-detect just before writing
sendline("$ErrorActionPreference='SilentlyContinue'")
sendline("$pdrv = (Get-Volume | ? FileSystemLabel -eq 'CIRCUITPY' | Select -Expand DriveLetter -First 1)")
sendline("if (-not $pdrv) { $root = (Get-PSDrive -PSProvider FileSystem | ? { Test-Path ($_.Root + 'code.py') } | Select -Expand Root -First 1); if ($root) { $pdrv = $root.Substring(0,1) } }")
sendline("if ($pdrv) { $P = ($pdrv + ':') } else { $P = 'D:' }")
sendline("Start-Sleep -Milliseconds 1500")   # give the mass-storage more time

sendline("$ts = Get-Date -Format o")
sendline("$hn = $env:COMPUTERNAME")
sendline("$ip = (Get-NetIPConfiguration | ? {$_.IPv4DefaultGateway -ne $null}).IPv4Address.IPAddress")
sendline("if (-not $ip) { $ip = (Get-NetIPAddress -AddressFamily IPv4 | ? { $_.IPAddress -notmatch '^127\\.|^169\\.254\\.' } | Select -ExpandProperty IPAddress -First 1) }")

# Use plain concatenation for path (avoids odd Join-Path quirks with drive roots)
sendline("$log = $P + '\\pico_ips.txt'")
sendline("$line = \"$ts`t$hn`t$ip`t" + ADMIN_USER + "`t$pw_note\"")

# Ensure file exists
sendline("if (-not (Test-Path $log)) { New-Item -ItemType File -Path $log -Force | Out-Null }")

# Try up to 5 times using 3 methods
sendline("$ok=$false; for($i=0;$i -lt 5 -and -not $ok;$i++){")
sendline("  try { $line | Out-File -FilePath $log -Append -Encoding ascii; $ok=$true } catch {}")
sendline("  if (-not $ok) { try { [System.IO.File]::AppendAllText($log, $line + [Environment]::NewLine, [Text.Encoding]::ASCII); $ok=$true } catch {} }")
sendline("  if (-not $ok) { try { cmd /c \"echo $line>> `\"$P\\pico_ips.txt`\"\" | Out-Null; $ok=$true } catch {} }")
sendline("  if (-not $ok) { Start-Sleep -Milliseconds 600 }")
sendline("}")

# Show result
sendline("if ($ok -and (Test-Path $log)) { Write-Host ('[log] Updated: ' + $log); Get-Content $log -Tail 5 } else { Write-Host '[log] FAILED to write log.' }")

# G) Status to screen
sendline("Get-Service sshd | Format-Table Name,Status,StartType -Auto")
sendline("if (Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue) "
        "{ Write-Host '[sshd] Listening on port 22' } else { Write-Host '[sshd] Not listening yet' }")
