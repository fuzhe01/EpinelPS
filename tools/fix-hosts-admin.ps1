# 修复 hosts 里的黑洞地址（需要管理员权限）
#
# 问题：na.fleetlogd.com 和 sentry.io 被写成 255.255.221.21
#       这是保留地址，Windows DNS 解析器直接返回失败（curl_error=6）
#       启动器上报遥测时反复失败，可能影响公告弹窗
#
# 修复：改成 127.0.0.1（服务端已实现 telemetry 拦截，会返回成功）

$ErrorActionPreference = 'Stop'
$hosts = 'C:\Windows\System32\drivers\etc\hosts'

# 检查管理员
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '需要管理员权限，正在提权...' -ForegroundColor Yellow
    Start-Process pwsh -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath
    ) -Verb RunAs
    exit
}

Write-Host '=== 1. 备份 hosts ===' -ForegroundColor Cyan
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bak = "$hosts.bak-$stamp"
Copy-Item $hosts $bak -Force
Write-Host "  OK $bak"

Write-Host ''
Write-Host '=== 2. 修正黑洞地址 ===' -ForegroundColor Cyan
$lines = Get-Content $hosts
$changed = 0
$new = foreach ($line in $lines) {
    if ($line -match '^255\.255\.221\.21\s+(na\.fleetlogd\.com|sentry\.io)') {
        $fixed = $line -replace '^255\.255\.221\.21', '127.0.0.1'
        Write-Host "  $($line.Trim())  -->  $($fixed.Trim())"
        $changed++
        $fixed
    } else {
        $line
    }
}

if ($changed -eq 0) {
    Write-Host '  没有需要修正的条目' -ForegroundColor Yellow
} else {
    $new | Set-Content $hosts -Encoding utf8
    Write-Host "  已修正 $changed 条" -ForegroundColor Green
}

Write-Host ''
Write-Host '=== 3. 刷新 DNS ===' -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Write-Host '  OK'

Write-Host ''
Write-Host '=== 4. 验证 ===' -ForegroundColor Cyan
foreach ($d in @('na.fleetlogd.com', 'sentry.io')) {
    try {
        $ips = [System.Net.Dns]::GetHostAddresses($d) | ForEach-Object { $_.IPAddressToString }
        Write-Host "  OK $d -> $($ips -join ', ')" -ForegroundColor Green
    } catch {
        Write-Host "  FAIL $d" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '完成。按任意键退出...' -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
