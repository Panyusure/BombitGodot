@echo off
setlocal
cd /d "%~dp0"
set "EXE=%~dp0BombitGodot.console.exe"
if not exist "%EXE%" set "EXE=%~dp0build\windows\BombitGodot.console.exe"
if not exist "%EXE%" (
  echo BombitGodot.console.exe not found.
  exit /b 1
)
"%EXE%" --headless --no-header -- --mcp
exit /b %ERRORLEVEL%