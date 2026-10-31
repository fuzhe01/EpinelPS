# 启动 EpinelPS 服务端并等待就绪
$ErrorActionPreference = 'Continue'

$ServerDir = 'D:\EpinelPS\out'
$Exe       = Join-Path $ServerDir 'EpinelPS.exe'
$LogFile   = Join-Path $ServerDir 'logs\server-out.log'

if (-not (Test-Path $Exe)) {
    Write-Host "      ERROR: EpinelPS.exe not found at $Exe"
    exit 1
}

# 清掉残留进程
Get-Process -Name EpinelPS -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "      Stopping leftover PID $($_.Id)"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# 启动（最小化窗口，方便查看/关闭）
Write-Host "      Launching EpinelPS.exe ..."
Start-Process -FilePath $Exe -WorkingDirectory $ServerDir -WindowStyle Minimized

# 等待 443 就绪，最多 60 秒
Write-Host "      Waiting for port 443 ..."
$ok = $false
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Seconds 1
    if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
        $ok = $true
        break
    }
}

if ($ok) {
    Write-Host "      Server is ready on port 443 (took $i s)"
    exit 0
} else {
    Write-Host "      WARNING: server did not open port 443 within 60s"
    Write-Host "               Check log: $LogFile"
    exit 2
}
