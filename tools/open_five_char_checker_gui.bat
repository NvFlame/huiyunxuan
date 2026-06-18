@echo off
cd /d "%~dp0.."
python tools\five_char_prosody_gui.py
if errorlevel 1 pause
