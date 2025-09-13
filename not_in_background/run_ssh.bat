@echo off
REM run_ssh.bat — runs install-ssh.ps1 from this same folder with elevation,
REM leaving no files behind on the Windows PC.

setlocal
set SRC=%~dp0install-ssh.ps1
set DST=%TEMP%\install-ssh.ps1

if not exist "%SRC%" (
  echo [!] Could not find install-ssh.ps1 next to this .bat
  pause
  exit /b 1
)

copy /Y "%SRC%" "%DST%" >nul
if errorlevel 1 (
  echo [!] Failed to copy to %DST%
  pause
  exit /b 1
)

REM Launch elevated PowerShell to run the temp copy; wait for it to finish
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p = Start-Process PowerShell -Verb RunAs -PassThru -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"\"%DST%\"\"'; ^
   $p.WaitForExit()"

REM Clean up the temp copy
del /F /Q "%DST%" >nul 2>&1

echo.
echo Done. (SSH should now be installed; no files left on this PC.)
pause
endlocal
