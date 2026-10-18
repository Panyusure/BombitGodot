# 导出 Windows / Web 并刷新 dist 绿色包
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$godot = "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

Write-Host "[1/4] Export Windows..." -ForegroundColor Cyan
& $godot --headless --path $root --export-release "Windows Desktop" "$root\build\windows\BombitGodot.exe"

Write-Host "[2/4] Export Web..." -ForegroundColor Cyan
& $godot --headless --path $root --export-release "Web" "$root\build\web\index.html"

Write-Host "[3/4] Refresh dist..." -ForegroundColor Cyan
$dist = Join-Path $root "dist\BombIt-Godot-v1.0-win64"
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null
Copy-Item "$root\build\windows\BombitGodot.exe", "$root\build\windows\BombitGodot.pck" $dist
Copy-Item "$root\README.md" (Join-Path $dist "README.md")
Copy-Item "$root\docs\绿色包说明.txt" (Join-Path $dist "README.txt")
New-Item -ItemType Directory -Path (Join-Path $dist "docs\screenshots") -Force | Out-Null
Copy-Item "$root\docs\screenshots\*.png" (Join-Path $dist "docs\screenshots")
Set-Content -Path (Join-Path $dist "启动游戏.bat") -Encoding ASCII -Value @'
@echo off
cd /d "%~dp0"
start "" "BombitGodot.exe"
'@

Write-Host "[4/4] Zip..." -ForegroundColor Cyan
$zip = Join-Path $root "dist\BombIt-Godot-v1.0-win64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $dist "*") -DestinationPath $zip -Force
Write-Host "Done: $zip" -ForegroundColor Green
