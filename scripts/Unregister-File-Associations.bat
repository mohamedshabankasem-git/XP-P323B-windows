@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0unregister_file_associations.ps1"
if errorlevel 1 (
  echo Removal failed.
  pause
  exit /b 1
)
echo.
echo XP-P323B file associations were removed.
pause
