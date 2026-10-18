@echo off
rem There is no pwsh on this machine (only Windows PowerShell 5.1), so run the
rem locked test runner through this .cmd shim from any shell (bash / cmd / powershell).
rem Keep this file ASCII-only: cmd.exe reads .cmd in the OEM codepage.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools_test_locked.ps1" %*
exit /b %ERRORLEVEL%
