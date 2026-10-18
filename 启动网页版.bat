@echo off
cd /d "%~dp0"
echo [BombIt] Serving build\web on http://127.0.0.1:8077/ ...
start "BombIt Web Server" /min cmd /c "python -m http.server 8077 --directory build\web"
timeout /t 2 /nobreak >nul
start "" "http://127.0.0.1:8077/"
