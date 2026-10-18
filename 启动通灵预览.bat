@echo off
cd /d "%~dp0"
rem 直接运行通灵柔光 MOTION ID 预览场景（不经过主菜单）。
rem 编辑器里也可以直接打开 soul_preview.tscn 后按 F6。
set "GODOT=E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=godot.exe"
start "" "%GODOT%" --path "%~dp0" "res://soul_preview.tscn"
