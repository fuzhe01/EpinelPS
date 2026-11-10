# 修复 aws-na-dr.intlgame.com 的 hosts 条目（需要管理员权限）
#
# 背景：
#   启动器登录前请求 POST https://aws-na-dr.intlgame.com/v2/dr/getsid
#   EpinelPS 没有实现 /v2/dr/getsid，重定向到本机会返回 404，
#   启动器因此弹「系统错误」/「ID: 4/404」。
#
#   手册第 5 章已有结论：这一行必须【不写】hosts，放行到真实 AWS。
#
# 本脚本：把 aws-na-dr.intlgame.com 从 hosts 里【删除】（注释掉）。

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
$bak = "$hosts.bak-awsdr-$stamp"
Copy-Item $hosts $bak -Force
Write-Host "  OK $bak"

Write-Host ''
Write-Host '=== 2. 注释掉 aws-na-dr.intlgame.com ===' -ForegroundColor Cyan
$lines = Get-Content $hosts
$changed = 0
$new = foreach ($line in $lines) {
    if ($line -match '^\s*\S+\s+aws-na-dr\.intlgame\.com\s*$') {
        Write-Host "  # $($line.Trim())"
        "# disabled by fix-awsdr-admin.ps1 ($stamp): server has no /v2/dr/getsid -- $($line.Trim())"
        $changed++
    } else {
        $line
    }
}

if ($changed -eq 0) {
    Write-Host '  没有需要处理的条目' -ForegroundColor Yellow
} else {
    $new | Set-Content $hosts -Encoding utf8
    Write-Host "  已注释 $changed 条" -ForegroundColor Green
}

Write-Host ''
Write-Host '=== 3. 刷新 DNS ===' -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Write-Host '  OK'

Write-Host ''
Write-Host '=== 4. 验证 ===' -ForegroundColor Cyan
try {
    $ips = [System.Net.Dns]::GetHostAddresses('aws-na-dr.intlgame.com') | ForEach-Object { $_.IPAddressToString }
    Write-Host "  aws-na-dr.intlgame.com -> $($ips -join ', ')" -ForegroundColor Green
    if ($ips -contains '127.0.0.1') {
        Write-Host '  WARN: 仍指向本机，可能还有其它规则' -ForegroundColor Yellow
    } else {
        Write-Host '  OK: 已放行到真实服务器' -ForegroundColor Green
    }
} catch {
    Write-Host '  FAIL: 解析失败' -ForegroundColor Red
}

Write-Host ''
Write-Host '完成。请完全关闭启动器后重新打开。' -ForegroundColor Cyan
Write-Host '按任意键退出...'
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
