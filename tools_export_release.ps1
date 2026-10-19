# 导出 Windows / Web 并刷新 dist 绿色包
# 绿色包内容与 docs/绿色包说明.txt 的【文件】清单保持一致。
param(
    [ValidatePattern('^[0-9]+\.[0-9]+(?:\.[0-9]+)?$')]
    [string]$Version = '2.0',
    [switch]$SkipWeb
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$godot = "E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$distRoot = [System.IO.Path]::GetFullPath((Join-Path $root 'dist'))
$dist = [System.IO.Path]::GetFullPath((Join-Path $distRoot "BombIt-Godot-v$Version-win64"))
if ([System.IO.Path]::GetDirectoryName($dist) -ne $distRoot) { throw 'Invalid package directory' }
New-Item -ItemType Directory -Path "$root\build\windows", $distRoot -Force | Out-Null

Write-Host "[1/4] Export Windows..." -ForegroundColor Cyan
# godot 会往 stderr 写 CLIBOOT 之类的行；EAP=Stop 下会被当成 NativeCommandError，
# 所以这一段临时放宽，改用退出码判定成败。
$ErrorActionPreference = "Continue"
& $godot --headless --path $root --export-release "Windows Desktop" "$root\build\windows\BombitGodot.exe" 2>&1 | ForEach-Object { Write-Host $_ }
$winExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($winExit -ne 0) { throw "Windows export failed: exit $winExit" }

Write-Host "[2/4] Export Web..." -ForegroundColor Cyan
if (-not $SkipWeb) {
New-Item -ItemType Directory -Path "$root\build\web" -Force | Out-Null
$ErrorActionPreference = "Continue"
& $godot --headless --path $root --export-release "Web" "$root\build\web\index.html" 2>&1 | ForEach-Object { Write-Host $_ }
$webExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($webExit -ne 0) { throw "Web export failed: exit $webExit" }
} else { Write-Host 'Skipped (Windows-only release).' }

Write-Host "[3/4] Refresh dist..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $dist) { Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null
Copy-Item "$root\build\windows\BombitGodot.exe", "$root\build\windows\BombitGodot.pck", "$root\build\windows\BombitGodot.console.exe" $dist
Copy-Item "$root\README.md" $dist
Copy-Item "$root\docs\绿色包说明.txt" (Join-Path $dist "README.txt")
Copy-Item "$root\启动CLI.bat", "$root\bombit-mcp.bat" $dist
New-Item -ItemType Directory -Path (Join-Path $dist "docs\screenshots"), (Join-Path $dist "mcp") -Force | Out-Null
Copy-Item "$root\docs\Godot-CLI与MCP.md", "$root\docs\迁移对照.md" (Join-Path $dist "docs")
Copy-Item "$root\docs\局域网联机.md", "$root\docs\发布说明-v$Version.md" (Join-Path $dist "docs")
Copy-Item "$root\docs\screenshots\*.png" (Join-Path $dist "docs\screenshots")

# MCP 样例不写死本机路径，解压到哪都能照着改。
$mcpSample = @'
{
  "mcpServers": {
    "bombit": {
      "command": "<把这里替换成绿色包内 BombitGodot.console.exe 的完整路径>",
      "args": ["--headless", "--no-header", "--", "--mcp"]
    }
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $dist "mcp\bombit-mcp.json"), $mcpSample, (New-Object System.Text.UTF8Encoding($false)))

Set-Content -Path (Join-Path $dist "启动游戏.bat") -Encoding ASCII -Value @'
@echo off
cd /d "%~dp0"
start "" "BombitGodot.exe"
'@

Write-Host "[4/4] Zip..." -ForegroundColor Cyan
$zip = Join-Path $distRoot "BombIt-Godot-v$Version-win64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $dist "*") -DestinationPath $zip -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText((Join-Path $distRoot 'SHA256SUMS.txt'), "$hash  $([System.IO.Path]::GetFileName($zip))`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Done: $zip" -ForegroundColor Green
