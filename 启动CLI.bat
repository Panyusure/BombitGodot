@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "EXE=%~dp0BombitGodot.console.exe"
if not exist "%EXE%" set "EXE=%~dp0build\windows\BombitGodot.console.exe"
if not exist "%EXE%" (
  echo BombitGodot.console.exe not found.
  pause
  exit /b 1
)
"%EXE%" --headless --no-header -- --cli play %*
echo.
echo CLI session closed.
pause