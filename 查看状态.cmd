@echo off
cd /d "%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\EpinelPS\tools\launch-all.ps1" -StatusOnly
pause
