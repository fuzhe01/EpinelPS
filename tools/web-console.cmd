@echo off
chcp 65001 >nul 2>&1
title EpinelPS Web 控制台
rem =====================================================================
rem  EpinelPS Web 控制台 —— 双击启动
rem
rem  双击           : 启动服务端并打开管理面板
rem  带参数运行      : 在 cmd 里执行  web-console.cmd -Status
rem                   可用参数: -Status  -Restart  -NoBrowser  -NoAutoLogin
rem =====================================================================

set "PS1=%~dp0web-console.ps1"

if not exist "%PS1%" (
    echo [XX] 找不到 web-console.ps1
    echo      预期位置: %PS1%
    pause
    exit /b 1
)

where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
)

if %errorlevel% neq 0 (
    echo.
    echo [!!] 脚本以退出码 %errorlevel% 结束
    pause
)
exit /b %errorlevel%
