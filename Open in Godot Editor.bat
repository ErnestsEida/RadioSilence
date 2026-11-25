@echo off
rem Opens the project in the Godot editor.
cd /d "%~dp0"
start "" "_engine\Godot_v4.4.1-stable_win64.exe" --editor --path .
