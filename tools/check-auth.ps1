# 私服认证链路健康自检
#
# 检查三件事：
#   1. 服务端在跑、443 在听
#   2. AuthSvr/Login 返回有效 PASETO token
#   3. 该 token 能被服务端解码出用户
#
# 任何一步失败就打印具体原因和修复建议。
# 退出码 0 = 健康，1 = 有问题。

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Continue'
$BaseUrl = 'https://www.jupiterlauncher.com'
$LobbyUrl = 'https://global-lobby.nikke-kr.com'

function Say($msg, $color = 'Gray') {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

$problems = @()

# ── 1. 服务端进程和端口 ──────────────────────────────────────────
$proc = Get-Process -Name EpinelPS -ErrorAction SilentlyContinue
if (-not $proc) {
    $problems += '服务端进程未运行（EpinelPS.exe）'
    Say '  [1] 服务端进程           FAIL 未运行' 'Red'
}
else {
    $listening = [bool](Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue)
    if (-not $listening) {
        $problems += '443 端口未监听（服务端启动失败或还在加载）'
        Say '  [1] 服务端进程           FAIL 443 未监听' 'Red'
    }
    else {
        Say "  [1] 服务端进程           OK   PID $($proc.Id), 443 监听中" 'Green'
    }
}

# ── 2. TLS 证书 ─────────────────────────────────────────────────
$THUMB = 'B8C27EB20A0F128BCA489F58A725B445E9CFCEAC'
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'CurrentUser')
try {
    $store.Open('ReadOnly')
    $cert = $store.Certificates | Where-Object { $_.Thumbprint -eq $THUMB }
    if ($cert) {
        Say "  [2] TLS 证书（证书库）    OK   $THUMB" 'Green'
    }
    else {
        $problems += 'TLS 证书不在 CurrentUser\My（跑 tools\install-cert.ps1）'
        Say '  [2] TLS 证书（证书库）    FAIL 缺失' 'Red'
    }
}
catch {
    $problems += "读取证书库失败: $($_.Exception.Message)"
    Say '  [2] TLS 证书（证书库）    FAIL 读取失败' 'Red'
}
finally {
    $store.Close()
}

# ── 3. AuthSvr/Login 返回 PASETO ────────────────────────────────
$token = $null
try {
    $r = Invoke-WebRequest "$BaseUrl/api/v1/fleet.auth.game.AuthSvr/Login" -Method POST `
        -Body '{}' -ContentType 'application/json' -NoProxy -TimeoutSec 10 -UseBasicParsing
    $j = $r.Content | ConvertFrom-Json

    if (-not $j.biz_ticket) {
        $problems += 'AuthSvr/Login 返回空 biz_ticket（检查 LauncherController.LauncherLogin）'
        Say '  [3] AuthSvr/Login 凭据     FAIL biz_ticket 为空' 'Red'
    }
    elseif ($j.biz_ticket -notlike 'v4.local.*') {
        $problems += "AuthSvr/Login 返回的不是 PASETO token（实际: $($j.biz_ticket.Substring(0,[Math]::Min(20,$j.biz_ticket.Length)))）"
        Say '  [3] AuthSvr/Login 凭据     FAIL 非 PASETO 格式' 'Red'
    }
    else {
        $token = $j.biz_ticket
        Say "  [3] AuthSvr/Login 凭据     OK   PASETO len=$($token.Length), uid=$($j.uid)" 'Green'
    }
}
catch {
    $problems += "AuthSvr/Login 请求失败: $($_.Exception.Message)"
    Say '  [3] AuthSvr/Login 凭据     FAIL 请求失败' 'Red'
}

# ── 4. token 可被服务端解码 ─────────────────────────────────────
if ($token) {
    try {
        $body = @{ token = $token } | ConvertTo-Json -Compress
        $r = Invoke-WebRequest "$LobbyUrl/account/getuserinfo?seq=healthcheck" -Method POST `
            -Body $body -ContentType 'application/json' -NoProxy -TimeoutSec 10 -UseBasicParsing
        $j = $r.Content | ConvertFrom-Json
        if ($j.ret -eq 0 -and $j.uid) {
            Say "  [4] Token 解码            OK   uid=$($j.uid), email=$($j.email)" 'Green'
        }
        else {
            $problems += "Token 解码失败: ret=$($j.ret) msg=$($j.msg)"
            Say "  [4] Token 解码            FAIL ret=$($j.ret)" 'Red'
        }
    }
    catch {
        $problems += "Token 解码请求失败: $($_.Exception.Message)"
        Say '  [4] Token 解码            FAIL 请求失败' 'Red'
    }
}
else {
    Say '  [4] Token 解码            SKIP（无 token）' 'Yellow'
}

# ── 结论 ────────────────────────────────────────────────────────
if ($problems.Count -eq 0) {
    Say ''
    Say '  认证链路健康，可以直接进游戏。' 'Green'
    exit 0
}

Say ''
Say '  发现问题：' 'Red'
$problems | ForEach-Object { Say "    - $_" 'Red' }
Say ''
Say '  修复建议：' 'Yellow'
Say '    · 证书缺失      → pwsh -File D:\EpinelPS\tools\install-cert.ps1' 'Yellow'
Say '    · 服务端未运行  → 跑一键启动脚本，或看 out\logs\server-out.log' 'Yellow'
Say '    · 凭据为空/格式错 → 重新编译部署服务端（LauncherController 补丁）' 'Yellow'
Say '    · 仍然登录失败  → 删 last_user.dat + psd.dat 强制重登' 'Yellow'
exit 1