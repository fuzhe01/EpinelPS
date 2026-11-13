# NIKKE 私服 —— 完整启动器（保留 Flint 更新渠道 + 修复超时问题）
#
# 工作流：
#   1) 独立做一次服务端更新检查（复用 Flint 的 latest.json 渠道）
#   2) 用 epinelps-patcher 打补丁（幂等）
#   3) 启动 EpinelPS（不设超时）
#   4) 打开官方启动器，等你登录玩游戏
#   5) 可选：游戏退出后自动还原 official
#
param(
    [switch]$AutoRestore,
    [switch]$Offline,
    [switch]$RefreshDirect,
    [switch]$SkipUpdate,
    [switch]$StatusOnly
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ================= 配置 =================
$Root         = 'D:\EpinelPS'
$ServerDir    = Join-Path $Root 'out'
$ServerExe    = Join-Path $ServerDir 'EpinelPS.exe'
$PatcherDir   = Join-Path $Root 'Patch'
$Patcher      = Join-Path $PatcherDir 'epinelps-patcher.exe'
$Launcher     = 'D:\nikke\Launcher\nikke_launcher.exe'
$GameRoot     = 'D:\nikke'
$BackupDir    = 'D:\EpinelPS\backups'
$CheckUpdate  = Join-Path $PSScriptRoot 'check-update.ps1'
$Manifest     = Join-Path $ServerDir '.update-manifest.json'

function Step($n, $t) { Write-Host "[$n/6] $t" -ForegroundColor Cyan }
function Ok($m)       { Write-Host "      $m" -ForegroundColor Green }
function Warn2($m)    { Write-Host "      $m" -ForegroundColor Yellow }
function Info($m)     { Write-Host "      $m" -ForegroundColor DarkGray }

# ================= 管理员 =================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '需要管理员权限，正在提权...' -ForegroundColor Yellow
    $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    foreach ($sw in 'AutoRestore','Offline','RefreshDirect','SkipUpdate','StatusOnly') {
        if ((Get-Variable $sw -ValueOnly)) { $a += "-$sw" }
    }
    Start-Process -FilePath 'pwsh' -ArgumentList $a -Verb RunAs
    exit
}

# ================= 状态模式 =================
if ($StatusOnly) {
    Write-Host '=== 客户端补丁 ===' -ForegroundColor Cyan
    & $Patcher status --game-root $GameRoot
    Write-Host ''
    Write-Host '=== 服务端 ===' -ForegroundColor Cyan
    $p = Get-Process -Name EpinelPS -ErrorAction SilentlyContinue
    if ($p) { Write-Host "  运行中 (PID $($p.Id))" -ForegroundColor Green } else { Write-Host '  未运行' -ForegroundColor Yellow }
    if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) {
        Write-Host '  443 监听中' -ForegroundColor Green
    } else { Write-Host '  443 未监听' -ForegroundColor Yellow }
    Write-Host ''
    if (Test-Path $Manifest) {
        $j = Get-Content $Manifest -Raw | ConvertFrom-Json
        Write-Host "=== 更新清单: $($j.files.Count) 个文件 ===" -ForegroundColor Cyan
        ($j.files | Where-Object { $_.path -eq 'EpinelPS.exe' } | Select-Object -First 1) | ForEach-Object {
            Write-Host "  EpinelPS.exe $($_.size) 字节  sha256=$($_.sha256.Substring(0,16))..."
        }
    }
    Write-Host ''
    Write-Host '按任意键关闭...'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

Write-Host ''
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host '         NIKKE 私服  启动器' -ForegroundColor Cyan
Write-Host '   （保留官方更新渠道 + 修复 20 秒超时问题）' -ForegroundColor DarkCyan
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host ''
Step 1 '管理员权限 OK'

# ================= 2. 检查更新（GitHub）=================
Step 2 '检查服务端更新（GitHub Releases）...'
if ($SkipUpdate) {
    Info '已跳过（-SkipUpdate）'
} else {
    $localVer = $null
    if (Test-Path (Join-Path $Root 'config.json')) {
        try { $localVer = (Get-Content (Join-Path $Root 'config.json') -Raw | ConvertFrom-Json).hei_server_version } catch {}
    }

    $remote = $null
    if (Test-Path $CheckUpdate) {
        try {
            # check-update.ps1 -Json 只输出一行紧凑 JSON（无其他文本）
            $json = & pwsh -NoProfile -ExecutionPolicy Bypass -File $CheckUpdate -Json 2>$null
            $line = ($json | Where-Object { $_ -match '^\s*\{' } | Select-Object -First 1)
            if ($line) { $remote = $line | ConvertFrom-Json }
            else { Warn2 "更新检查返回空结果" }
        } catch {
            Warn2 "检查更新失败: $($_.Exception.Message)"
        }
    }

    if (-not $remote -or $remote.error) {
        Warn2 'GitHub 更新源不可用（继续用当前版本）'
    } else {
        Info "本地版本: $localVer"
        Info "远程版本: $($remote.Version)"

        if ($localVer -eq $remote.Version) {
            Ok '已是最新版本'
        } else {
            Warn2 "发现新版本: $($remote.Version)"
            if ($remote.Size)   { Info ("大小: {0:N1} MB" -f ($remote.Size/1MB)) }
            if ($remote.Notes)  { Info "说明: $($remote.Notes -replace "`n",' ')" }
            Write-Host ''
            Write-Host '      是否现在更新服务端？' -ForegroundColor Yellow
            Write-Host '        [1] 更新（保留存档与缓存）' -ForegroundColor White
            Write-Host '        [2] 跳过，用当前版本启动' -ForegroundColor White
            Write-Host ''
            $ans = Read-Host '      请输入 1 或 2（默认 2）'
            if ($ans -eq '1') {
                $stage = Join-Path $Root '.update-staging'
                try {
                    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
                    New-Item -ItemType Directory -Path $stage -Force | Out-Null
                    $arcName = $remote.Asset
                    $arcPath = Join-Path $stage $arcName
                    Info "下载: $arcName"
                    (New-Object System.Net.WebClient).DownloadFile($remote.Url, $arcPath)
                    Ok "下载完成: $([math]::Round((Get-Item $arcPath).Length/1MB,1)) MB"

                    # SHA256 校验
                    if ($remote.Sha256) {
                        $h = (Get-FileHash $arcPath -Algorithm SHA256).Hash.ToLower()
                        if ($h -eq $remote.Sha256.ToLower()) { Ok 'SHA256 校验通过' }
                        else {
                            Warn2 "SHA256 不匹配！"
                            Warn2 "  预期: $($remote.Sha256)"
                            Warn2 "  实际: $h"
                            Warn2 '更新已中止'
                            Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
                            throw 'checksum mismatch'
                        }
                    } else { Info '（无 SHA256，跳过校验）' }

                    # 备份旧服务端
                    $bak = Join-Path $Root ("Server.bak-" + (Get-Date -f yyyyMMdd-HHmmss))
                    Copy-Item $ServerDir $bak -Recurse -Force
                    Ok "旧服务端已备份: $(Split-Path $bak -Leaf)"

                    # 解压
                    Info '解压中...'
                    & tar.exe -xzf $arcPath -C $stage 2>&1 | Out-Null
                    $ex = Get-ChildItem $stage -Directory | Select-Object -First 1
                    if ($ex) {
                        Get-ChildItem $ex.FullName -Force | ForEach-Object {
                            if ($_.Name -in @('db.json','epinelps.db','epinelps.db-shm','epinelps.db-wal','cache','logs')) {
                                Info "保留: $($_.Name)"
                            } else {
                                Copy-Item $_.FullName (Join-Path $ServerDir $_.Name) -Recurse -Force -ErrorAction SilentlyContinue
                            }
                        }
                        Ok '服务端已更新（存档与缓存已保留）'
                    }

                    # 记录新版本
                    if (Test-Path (Join-Path $Root 'config.json')) {
                        $cfg = Get-Content (Join-Path $Root 'config.json') -Raw | ConvertFrom-Json
                        $cfg.hei_server_version = $remote.Version
                        $cfg | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Root 'config.json') -Encoding utf8
                    }
                    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    Warn2 "更新失败: $($_.Exception.Message)"
                    Warn2 '继续用当前版本启动'
                    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else { Info '已跳过更新' }
        }
    }
}

# ================= 3. 清理 + 备份 =================
Step 3 '清理残留进程 + 备份存档...'
$left = Get-Process -Name EpinelPS -ErrorAction SilentlyContinue
if ($left) {
    $left | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; Info "停止 PID $($_.Id)" }
    Start-Sleep -Seconds 3
}

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($f in @('db.json','epinelps.db')) {
    $src = Join-Path $ServerDir $f
    if (Test-Path $src) { Copy-Item $src (Join-Path $BackupDir "$f.$stamp") -Force }
}
Get-ChildItem $BackupDir -Filter 'db.json.*' | Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 20 | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
Ok "存档已备份（保留最近 $((Get-ChildItem $BackupDir -Filter 'db.json.*' | Measure-Object).Count) 份）"

# ================= 4. 打补丁 =================
Step 4 '应用客户端补丁（epinelps-patcher）...'
if (Test-Path $Patcher) {
    $pArgs = @('local','--game-root',$GameRoot,'--resource-dir',$PatcherDir)
    if ($Offline)       { $pArgs += '--offline' }
    if ($RefreshDirect) { $pArgs += '--refresh-direct' }
    & $Patcher @pArgs 2>&1 | ForEach-Object { Ok $_ }

    # 补 match 域名（patcher 的 --direct 用的是真实 IP，不是本机）
    $hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $hl = Get-Content $hostsFile -ErrorAction SilentlyContinue
    if (-not ($hl | Where-Object { $_ -match '^\s*127\.0\.0\.1\s+\S+match\.nikke-kr\.com' })) {
        $idx = ($hl | Select-String -Pattern '127\.0\.0\.1 jp-lobby' | Select-Object -First 1).LineNumber
        $add = @('jp-match','kr-match','global-match','sea-match','hmt-match') | ForEach-Object { "127.0.0.1 $_.nikke-kr.com" }
        $new = @()
        for ($i=0; $i -lt $hl.Count; $i++) { $new += $hl[$i]; if ($i -eq ($idx-1)) { $new += $add } }
        if (-not $idx) { $new += $add }
        Set-Content -Path $hostsFile -Value $new -Encoding utf8
        ipconfig /flushdns | Out-Null
        Ok '已补充 match 对战域名重定向'
    }

    # CDN 测速排序（资源下载慢的主因）
    if ($RefreshDirect -or -not (Get-Content $hostsFile | Where-Object { $_ -match 'fastest first, measured' })) {
        Info '测速 CDN 节点（选最快的）...'
        $st = Join-Path $PSScriptRoot 'speedtest-cdn.ps1'
        if (Test-Path $st) {
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $st 2>&1 | ForEach-Object { Info $_ }
        }
    } else {
        Info 'CDN IP 已按测速排序（-RefreshDirect 可重测）'
    }
} else {
    Warn2 "找不到 patcher: $Patcher"
}

# ================= 5. 启动服务端 =================
Step 5 '启动 EpinelPS 服务端...'
if (-not (Test-Path $ServerExe)) { Warn2 "找不到: $ServerExe"; exit 1 }

# TLS 证书必须先在 CurrentUser\My：服务端在本机解析 site.pfx 会失败
# （PKCS#12 报"指定的网络密码不正确"/"拒绝访问"），改为从证书库按指纹加载。
$certScript = Join-Path $Root 'tools\install-cert.ps1'
if (Test-Path $certScript) {
    & pwsh -NoProfile -File $certScript -Quiet
    if ($LASTEXITCODE -ne 0) { Warn2 'TLS 证书准备失败，服务端可能无法监听 443' }
}

# 必须用 cmd start（Start-Process 在非交互会话会阻塞）
& cmd.exe /c "start `"EpinelPS`" /MIN /D `"$ServerDir`" `"$ServerExe`" --headless"
$ok = $false
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Seconds 1
    if (Get-NetTCPConnection -LocalPort 443 -State Listen -ErrorAction SilentlyContinue) { $ok = $true; break }
}
if ($ok) { Ok "服务端已就绪（${i}s）" }
else { Warn2 '端口未就绪，检查 logs\server-out.log'; exit 1 }

# 认证链路自检：确认 AuthSvr/Login 能返回可解码的 PASETO token。
# 这一步失败的话，游戏会报 "Login failed, please login from launcher again."
$authCheck = Join-Path $Root 'tools\check-auth.ps1'
if (Test-Path $authCheck) {
    & pwsh -NoProfile -File $authCheck
    if ($LASTEXITCODE -ne 0) {
        Warn2 '认证自检未通过（见上方详情）。游戏可能登录失败。'
        Warn2 '  · 若提示凭据为空/非 PASETO：服务端 exe 不是最新编译版本'
        Warn2 '  · 若 token 解码失败：删掉 %APPDATA%\nikke_launcher\last_user.dat 和 psd.dat 后重登'
    } else {
        Ok '认证链路正常'
    }
}

# ================= 6. 打开游戏 =================
Step 6 '打开游戏启动器...'
Write-Host ''
Write-Host '---------------------------------------------------' -ForegroundColor Green
Write-Host '  账号: 2863329208@qq.com    密码: 123456' -ForegroundColor White
Write-Host '  管理面板: https://global-lobby.nikke-kr.com/admin/' -ForegroundColor White
Write-Host "  存档备份: $BackupDir" -ForegroundColor DarkGray
Write-Host '---------------------------------------------------' -ForegroundColor Green
Write-Host ''

if (Test-Path $Launcher) {
    Start-Process -FilePath $Launcher
    Ok '启动器已打开'
} else { Warn2 "找不到: $Launcher" }

Write-Host ''
Write-Host '  服务端在最小化窗口运行 —— 关掉它游戏会掉线' -ForegroundColor Yellow
Write-Host '  本窗口可以关闭' -ForegroundColor DarkGray
Write-Host ''

# ================= 可选：自动还原 =================
if ($AutoRestore) {
    Write-Host '  [自动还原] 等待游戏退出（最多 4 小时，Ctrl+C 可中断）...' -ForegroundColor Magenta
    $deadline = (Get-Date).AddHours(4)
    $seen = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $g = Get-Process -Name nikke -ErrorAction SilentlyContinue
        if ($g) { $seen = $true } elseif ($seen) { break }
    }
    if ($seen) {
        Write-Host ''
        Write-Host '  游戏已退出，还原 official...' -ForegroundColor Cyan
        Get-Process -Name EpinelPS -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        & $Patcher official --game-root $GameRoot 2>&1 | ForEach-Object { Ok $_ }
        Write-Host '  已恢复 official 状态' -ForegroundColor Green
    } else { Warn2 '未检测到游戏启动，跳过还原' }
}

Write-Host ''
Write-Host '按任意键关闭...' -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

