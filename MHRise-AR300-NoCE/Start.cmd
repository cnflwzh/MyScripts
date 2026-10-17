@echo off
setlocal
cd /d "%~dp0"
set "RISE_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "RISE_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
echo Monster Hunter Rise - Rank Editor v2.1 - No Cheat Engine
echo.
echo Save in-game first and stay in an offline village.
echo Edit options apply without further confirmation.
echo.
echo 1. Inspect current ranks (read only)
echo 2. Back up saves and set AR 300
echo 3. Set Hunter Rank (HR 9-999)
echo 4. Set Master Rank (MR 7-999)
echo Q. Exit
choice /C 1234Q /N /M "Choose 1, 2, 3, 4 or Q: "
if errorlevel 5 exit /b 0
if errorlevel 4 goto master
if errorlevel 3 goto hunter
if errorlevel 2 goto modify
if errorlevel 1 goto inspect
exit /b 0
:inspect
"%RISE_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0MHRise-AR300.ps1" -Action Inspect -BackupDirectory "%~dp0backups"
goto done
:modify
"%RISE_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0MHRise-AR300.ps1" -Action SetAR300 -BackupDirectory "%~dp0backups"
goto done
:hunter
"%RISE_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0MHRise-AR300.ps1" -Action SetHR -BackupDirectory "%~dp0backups"
goto done
:master
"%RISE_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0MHRise-AR300.ps1" -Action SetMR -BackupDirectory "%~dp0backups"
:done
echo.
pause
endlocal
