# 更新官方代码并重放本地补丁
param(
    [switch]$NoBuild,
    [switch]$Abort,
    [switch]$Status
)

$ErrorActionPreference = 'Continue'
$Repo = 'D:\EpinelPS'
$Out  = Join-Path $Repo 'out'

function Step($n, $t) { Write-Host ""; Write-Host "[$n] $t" -ForegroundColor Cyan }
function Ok($m)       { Write-Host "    OK  $m" -ForegroundColor Green }
function Warn2($m)    { Write-Host "    !!  $m" -ForegroundColor Yellow }
function Err2($m)     { Write-Host "    XX  $m" -ForegroundColor Red }

function RunGit {
    param([string[]]$cmd)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git.exe'
    $psi.WorkingDirectory = $Repo
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
$argStr = '-C "' + $Repo + '"'
    foreach ($a in $cmd) {
        if ($a -match '\s') { $argStr += ' "' + $a + '"' } else { $argStr += ' ' + $a }
    }
    $psi.Arguments = $argStr
    $p = [System.Diagnostics.Process]::Start($psi)
    $so = $p.StandardOutput.ReadToEnd()
    $se = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    $lines = @()
    if ($so) { $lines += ($so -split "`r?`n" | Where-Object { $_ -ne '' }) }
    if ($se) { $lines += ($se -split "`r?`n" | Where-Object { $_ -ne '' }) }
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $lines }
}

if ($Status) {
    Write-Host '=== Git 状态 ===' -ForegroundColor Cyan
    Write-Host ("  分支   : " + ((RunGit @('rev-parse','--abbrev-ref','HEAD')).Out -join ' '))
    Write-Host ("  HEAD   : " + ((RunGit @('log','-1','--oneline')).Out -join ' '))
    $d = RunGit @('status','--porcelain')
    Write-Host ("  工作区 : " + $(if ($d.Out) { '有未提交改动' } else { '干净' }))
    if (Test-Path (Join-Path $Repo '.git\rebase-merge')) { Warn2 '有未完成的 rebase' }
    Write-Host ''
    Write-Host '=== 分支 ===' -ForegroundColor Cyan
    (RunGit @('branch','-vv')).Out | ForEach-Object { "  $_" }
    Write-Host ''
    Write-Host '=== 本地补丁 ===' -ForegroundColor Cyan
    $pt = RunGit @('log','main..my-patches','--oneline')
    if ($pt.Out) { $pt.Out | ForEach-Object { "  $_" } } else { Write-Host '  (无)' }
    exit 0
}

if ($Abort) {
    Step 1 '中止 rebase'
    $r = RunGit @('rebase','--abort')
    if ($r.Code -eq 0) { Ok '已中止' } else { Warn2 '没有进行中的 rebase' }
    exit 0
}

Write-Host ''
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host '      更新官方代码 + 重放本地补丁' -ForegroundColor Cyan
Write-Host '===================================================' -ForegroundColor Cyan

Step 1 '检查工作区'
$d = RunGit @('status','--porcelain')
if ($d.Out) {
    Err2 '工作区有未提交改动：'
    $d.Out | ForEach-Object { Write-Host "        $_" }
    Write-Host ''
    Warn2 '请先提交: git add -A ; git commit -m "说明"'
    exit 1
}
Ok '干净'

Step 2 '拉取官方更新'
$r = RunGit @('fetch','origin','--prune')
if ($r.Code -ne 0) {
    Err2 'fetch 失败：'
    $r.Out | ForEach-Object { Write-Host "        $_" }
    exit 1
}
Ok '完成'

$o = ((RunGit @('rev-parse','main')).Out -join '')
$n = ((RunGit @('rev-parse','origin/main')).Out -join '')
if ($o -eq $n) { Ok ("main 无变化 (" + $o.Substring(0,8) + ")") }
else { Ok ("main 更新: " + $o.Substring(0,8) + " -> " + $n.Substring(0,8)) }

Step 3 '更新 main'
$r = RunGit @('checkout','main')
if ($r.Code -ne 0) { Err2 "切换失败"; exit 1 }
$r = RunGit @('merge','--ff-only','origin/main')
if ($r.Code -ne 0) {
    Err2 '无法快进合并：'
    $r.Out | ForEach-Object { Write-Host "        $_" }
    RunGit @('checkout','my-patches') | Out-Null
    exit 1
}
Ok ("main = " + ((RunGit @('rev-parse','--short','HEAD')).Out -join ''))

Step 4 '重放补丁到新 main'
$r = RunGit @('checkout','my-patches')
if ($r.Code -ne 0) { Err2 "切换失败"; RunGit @('checkout','main') | Out-Null; exit 1 }

$r = RunGit @('rebase','main')
if ($r.Code -ne 0) {
    Write-Host ''
    Err2 '变基冲突'
    Write-Host ''
    Write-Host '  冲突文件:' -ForegroundColor Yellow
    (RunGit @('diff','--name-only','--diff-filter=U')).Out | ForEach-Object { Write-Host "    $_" }
    Write-Host ''
    Write-Host '  解决方式:' -ForegroundColor Yellow
    Write-Host '    1) 编辑冲突文件'
    Write-Host '    2) git add <文件>'
    Write-Host '    3) git rebase --continue'
    Write-Host ''
    Write-Host '  或放弃: git rebase --abort' -ForegroundColor Yellow
    exit 2
}
Ok '补丁已重放'

if ($NoBuild) {
    Step 5 '跳过编译'
    Warn2 'out 里的 exe 仍是旧版'
    exit 0
}

Step 5 '编译'
$sw = [Diagnostics.Stopwatch]::StartNew()
Push-Location $Repo
try {
    $bo = & dotnet publish EpinelPS -c Release 2>&1
    $bc = $LASTEXITCODE
} finally { Pop-Location }
$sw.Stop()

if ($bc -ne 0) {
    Err2 '编译失败'
    $bo | Select-Object -Last 15 | ForEach-Object { Write-Host "        $_" }
    exit 1
}
Ok ("完成 (" + [math]::Round($sw.Elapsed.TotalSeconds,0) + " 秒)")

$pubExe = Join-Path $Repo 'EpinelPS\bin\Release\net10.0\win-x64\publish\EpinelPS.exe'
if (-not (Test-Path $pubExe)) { Err2 "找不到编译产物"; exit 1 }

Step 6 '部署'
$run = Get-Process -Name EpinelPS -ErrorAction SilentlyContinue
if ($run) {
    Warn2 ("服务端运行中 (PID " + $run.Id + ")")
    $ans = Read-Host '    停止并部署? [y/N]'
    if ($ans -notmatch '^[Yy]') {
        Warn2 '已取消。编译产物:'
        Write-Host "        $pubExe"
        exit 0
    }
    Stop-Process -Id $run.Id -Force
    Start-Sleep -Seconds 3
    Ok '服务端已停止'
}

Copy-Item $pubExe (Join-Path $Out 'EpinelPS.exe') -Force
Ok 'EpinelPS.exe 已更新'

$vi = (Get-Item (Join-Path $Out 'EpinelPS.exe')).VersionInfo
$sh = (Get-FileHash (Join-Path $Out 'EpinelPS.exe') -Algorithm SHA256).Hash.Substring(0,16)
Write-Host "        ProductVersion: $($vi.ProductVersion)"
Write-Host "        SHA256: $sh..."

Write-Host ''
Write-Host '===================================================' -ForegroundColor Green
Write-Host '   完成' -ForegroundColor Green
Write-Host '===================================================' -ForegroundColor Green
Write-Host ("  main      : " + ((RunGit @('rev-parse','--short','main')).Out -join ''))
Write-Host ("  my-patches: " + ((RunGit @('rev-parse','--short','my-patches')).Out -join ''))
Write-Host ''
Write-Host '  下一步: 双击桌面「NIKKE 私服」' -ForegroundColor Yellow

