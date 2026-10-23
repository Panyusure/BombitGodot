@echo off
cd /d "%~dp0"
set "GODOT=E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=godot.exe"
start "" "%GODOT%" --path "%~dp0" "res://character_walk_preview.tscn"
