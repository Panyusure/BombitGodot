@echo off
cd /d "%~dp0"
if not exist "build\windows\BombitGodot.exe" (
  echo [BombIt] Windows build not found. Run tools_export_release.ps1 first.
  pause
  exit /b 1
)
start "" "build\windows\BombitGodot.exe"
