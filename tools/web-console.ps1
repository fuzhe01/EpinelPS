# ============================================================================
#  EpinelPS 一键启动 Web 控制台
#  用途：双击即可 —— 自动检查/启动服务端，验证面板可用，然后打开浏览器
#
#  用法：
#    直接双击            -> 自动：起服务端 -> 验证 -> 打开面板
#    右键"使用 PowerShell 运行" 并加参数：
#       -NoBrowser       只启动服务端，不开浏览器
#       -Restart         强制重启服务端（即使已在运行）
#       -Status          只查看状态，不做任何改动
#       -NoAutoLogin     打开面板但不自动填入账号密码
# ============================================================================
param(
    [switch]$NoBrowser,
    [switch]$Restart,
    [switch]$Status,
    [switch]$NoAutoLogin
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ============================== 配置区 ==============================
$Root       = 'D:\EpinelPS'
$ServerDir  = Join-Path $Root 'out'
$ServerExe  = Join-Path $ServerDir 'EpinelPS.exe'
$LogDir     = Join-Path $ServerDir 'logs'
$OutLog     = Join-Path $LogDir 'server-out.log'   # 仅当用本脚本从后台启动时才有
$AppLog     = Join-Path $LogDir ('app-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))  # log4net 每天一个，始终有

# 面板地址：用域名（证书 SAN 匹配，浏览器不会报证书错误）
# 注意：不要用 127.0.0.1，证书里没有 IP 的 SAN，会提示"证书名称不匹配"
$PanelUrl   = 'https://global-lobby.nikke-kr.com/admin/'
$HostMarker = 'global-lobby.nikke-kr.com'

# 面板账号（登录页的账号密码；改密码后请同步这里）
$AdminUser  = '2863329208@qq.com'
$AdminPass  = '123456'
# ===================================================================

function Line { Write-Host ('-' * 64) -ForegroundColor DarkGray }
function Ok($m)   { Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!!]   $m" -ForegroundColor Yellow }
function Err($m)  { Write-Host "  [XX]   $m" -ForegroundColor Red }
function Info($m) { Write-Host "         $m" -ForegroundColor DarkGray }
function Head($m) { Write-Host "`n$m" -ForegroundColor Cyan }

# ------------------------- 1. 管理员权限 -------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $Status) {
    Write-Host "需要管理员权限（要绑定 80/443 端口），正在提权..." -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    foreach ($sw in 'NoBrowser', 'Restart', 'Status', 'NoAutoLogin') {
        if ((Get-Variable $sw -ValueOnly)) { $argList += "-$sw" }
    }
    Start-Process -FilePath 'pwsh' -ArgumentList $argList -Verb RunAs
    exit
}

# ------------------------- 2. 状态检测辅助 -------------------------
function Get-ServerProc {
    Get-Process -Name EpinelPS -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Test-Port443 {
    [bool](Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue)
}

function Get-ActiveLog {
    # 优先用最新的日志：server-out.log（脚本启动时产生）或 app-YYYYMMDD.log（log4net，始终有）
    if ((Test-Path $OutLog) -and (Test-Path $AppLog)) {
        if ((Get-Item $OutLog).LastWriteTime -gt (Get-Item $AppLog).LastWriteTime) { return $OutLog }
        return $AppLog
    }
    if (Test-Path $OutLog) { return $OutLog }
    if (Test-Path $AppLog) { return $AppLog }
    return $null
}

function Test-Panel {
    # 走域名 + 跳过代理，模拟浏览器访问
    try {
        $r = Invoke-WebRequest -Uri $PanelUrl -NoProxy -TimeoutSec 15 -UseBasicParsing
        return $r.StatusCode -eq 200
    } catch { return $false }
}

# ------------------------- 3. 纯状态模式 -------------------------
if ($Status) {
    Line; Write-Host ' EpinelPS 状态' -ForegroundColor White; Line

    $p = Get-ServerProc
    if ($p) {
        Ok "服务端运行中 (PID $($p.Id)，启动于 $($p.StartTime))"
        if (Test-Port443) { Ok '443 端口监听正常' } else { Warn '443 未监听（可能还在启动）' }
        if (Test-Panel)   { Ok '面板可访问' } else { Warn '面板无响应' }
    } else {
        Warn '服务端未运行'
    }

    $hostsHas = (Select-String -Path 'C:\Windows\System32\drivers\etc\hosts' -Pattern "127\.0\.0\.1\s+$([regex]::Escape($HostMarker))" -Quiet -ErrorAction SilentlyContinue)
    if ($hostsHas) { Ok "hosts 已指向本机 ($HostMarker)" } else { Err "hosts 里缺少 $HostMarker 条目，面板将无法访问" }

    Head ' 最近日志'
    $activeLog = Get-ActiveLog
    if ($activeLog) {
        Info $activeLog
        Get-Content $activeLog -Tail 5 -ErrorAction SilentlyContinue | ForEach-Object { Info $_ }
    } else { Info '(暂无日志文件)' }
    Line
    Write-Host ''
    if (-not $NoBrowser -and $p) { Start-Process $PanelUrl }
    exit 0
}

# ------------------------- 4. 主流程 -------------------------
Line
Write-Host ' EpinelPS Web 控制台 —— 一键启动' -ForegroundColor White
Line

# 4.1 检查文件
if (-not (Test-Path $ServerExe)) {
    Err "找不到服务端: $ServerExe"
    Info '请先确认 D:\EpinelPS\out\EpinelPS.exe 存在'
    Line; Read-Host '按回车退出'; exit 1
}

# 4.2 hosts 检查（面板依赖域名解析到本机）
$hostsHas = (Select-String -Path 'C:\Windows\System32\drivers\etc\hosts' -Pattern "127\.0\.0\.1\s+$([regex]::Escape($HostMarker))" -Quiet -ErrorAction SilentlyContinue)
if ($hostsHas) {
    Ok 'hosts 已配置（面板域名指向本机）'
} else {
    Warn "hosts 缺少 $HostMarker，正在补上..."
    try {
        Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value "`n127.0.0.1 $HostMarker" -Encoding utf8 -ErrorAction Stop
        ipconfig /flushdns | Out-Null
        Ok 'hosts 已补充'
    } catch {
        Err "修改 hosts 失败: $($_.Exception.Message)"
        Info '面板可能无法打开；可用 https://127.0.0.1/admin/ 但会有证书警告'
    }
}

# 4.3 处理已在运行的服务端
$proc = Get-ServerProc
if ($proc -and -not $Restart) {
    Ok "服务端已在运行 (PID $($proc.Id))，直接复用"
} else {
    if ($proc) {
        Warn "停止现有服务端 (PID $($proc.Id))..."
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Info "启动 EpinelPS.exe ..."
    $newProc = Start-Process -FilePath $ServerExe -WorkingDirectory $ServerDir -PassThru -WindowStyle Minimized
    Ok "已启动 (PID $($newProc.Id))"

    # 4.4 等服务端就绪（最多 90 秒）
    Info '等待服务端就绪 ...'
    $ready = $false
    for ($i = 1; $i -le 90; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Port443) { $ready = $true; break }

        # 进程提前退出 = 启动失败
        if ($newProc.HasExited) {
            Err "服务端已退出 (退出码 $($newProc.ExitCode))"
            $al = Get-ActiveLog
            if ($al) {
                Head ' 日志末尾'
                Get-Content $al -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Info $_ }
                Info "完整日志: $al"
            }
            Line; Read-Host '按回车退出'; exit 2
        }
    }

    if (-not $ready) {
        Err '服务端 90 秒内未监听 443'
        Info "请检查日志: $OutLog"
        Line; Read-Host '按回车退出'; exit 3
    }
    Ok "服务端就绪（耗时 ${i}s）"
}

# 4.5 验证面板真的可用
Info '验证管理面板 ...'
$panelOk = $false
for ($i = 1; $i -le 20; $i++) {
    if (Test-Panel) { $panelOk = $true; break }
    Start-Sleep -Seconds 1
}
if ($panelOk) { Ok '面板响应正常 (HTTP 200)' } else { Warn '面板暂无响应，稍后手动刷新试试' }

# 4.6 提示信息
Head ' 就绪'
Info "面板地址 : $PanelUrl"
Info "登录账号 : $AdminUser"
Info "登录密码 : $AdminPass"
Info "服务端日志: $(Get-ActiveLog)"
Info ''
Info '提示：改完数据后需在游戏里重新登录才会生效'
Line

# 4.7 打开浏览器
if (-not $NoBrowser) {
    Start-Process $PanelUrl
    Ok '已在浏览器中打开面板'
    if (-not $NoAutoLogin) {
        Info ''
        Info "（本脚本无法自动填表，请手动输入上面的账号密码）"
    }
}

Write-Host ''
Write-Host ' 服务端在后台最小化运行。要关闭它：任务管理器结束 EpinelPS.exe，' -ForegroundColor DarkGray
Write-Host ' 或运行  tools\web-console.cmd -Restart  前先停止。' -ForegroundColor DarkGray
Write-Host ''
Read-Host '按回车关闭此窗口（不影响服务端运行）'
