@echo off
cd /d "%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\EpinelPS\tools\update-official.ps1"
pause
