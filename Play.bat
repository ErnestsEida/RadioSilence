@echo off
rem Starts Radio Silence with the Godot engine in the _engine folder.
cd /d "%~dp0"
start "" "_engine\Godot_v4.4.1-stable_win64.exe" --path .
