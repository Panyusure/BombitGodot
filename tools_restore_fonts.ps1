# 还原项目所需字体
#
# 本工程使用的 msyh.ttc / msyhbd.ttc / consola*.ttf / impact.ttf 均为
# Windows 随附的商业授权字体，版权归 Microsoft / Monotype 所有，
# 因此不入版本库。克隆仓库后运行本脚本，从本机 C:\Windows\Fonts 复制。
#
# 用法：  pwsh -File tools_restore_fonts.ps1
#         （或在资源管理器中右键本文件 → 使用 PowerShell 运行）

$ErrorActionPreference = "Stop"

$dst = Join-Path $PSScriptRoot "assets\fonts"
New-Item -ItemType Directory -Force -Path $dst | Out-Null

# 文件名 -> 用途说明
$fonts = [ordered]@{
    "msyh.ttc"     = "UI 正文（Microsoft YaHei）"
    "msyhbd.ttc"   = "UI 粗体（Microsoft YaHei Bold）"
    "consola.ttf"  = "等宽标签（Consolas）"
    "consolab.ttf" = "等宽粗体（Consolas Bold）"
    "impact.ttf"   = "大号标题 / 编号（Impact）"
}

$srcDir = Join-Path $env:WINDIR "Fonts"
$missing = @()

foreach ($name in $fonts.Keys) {
    $src = Join-Path $srcDir $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $dst $name) -Force
        $kb = [math]::Round((Get-Item -LiteralPath $src).Length / 1KB)
        Write-Host ("[OK]   {0,-12} {1,8} KB   {2}" -f $name, $kb, $fonts[$name])
    } else {
        $missing += $name
        Write-Warning ("[缺失] {0,-12} 未找到：{1}" -f $name, $src)
    }
}

Write-Host ""
if ($missing.Count -gt 0) {
    Write-Warning "有 $($missing.Count) 个字体未能还原：$($missing -join ', ')"
    Write-Warning "请手动将字体文件放入 assets\fonts\ 后，重新在 Godot 中打开项目以重建导入缓存。"
    exit 1
}

Write-Host "完成：字体已还原到 assets\fonts\"
Write-Host "请在 Godot 编辑器中重新打开项目（或执行 项目 → 重新导入），以重建 .godot\imported 缓存。"
