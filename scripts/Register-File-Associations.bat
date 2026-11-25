@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0register_file_associations.ps1" -ExePath "%~dp0xp_p323b_windows.exe"
if errorlevel 1 (
  echo Registration failed.
  pause
  exit /b 1
)
echo.
echo XP-P323B is now available in Open with and Send to.
pause
