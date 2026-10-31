# NIKKE CDN 测速排序工具
# 用途：客户端下载静态数据/资源慢时，自动测速并重排 hosts
param([switch]$Quiet)

$HostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$TestUrl   = 'https://cloud.nikke-kr.com/prdenv/153-cb882d4b30/staticdata/data/qa-261029-10b/578481/mpk/StaticData.pack'

# 候选 IP（已知的 CloudFront 边缘 + 从 DNS 动态获取）
$Candidates = New-Object System.Collections.Generic.List[string]

function Add-Cand($ip) {
    if ($ip -and $ip -match '^\d+\.\d+\.\d+\.\d+$' -and -not $Candidates.Contains($ip)) { $Candidates.Add($ip) }
}

# 1) 从现有 hosts 取
$hl = Get-Content $HostsFile -ErrorAction SilentlyContinue
$hl | Where-Object { $_ -match '^\s*\d+\.\d+\.\d+\.\d+\s+cloud\.nikke-kr\.com' } | ForEach-Object {
    if ($_ -match '^\s*(\d+\.\d+\.\d+\.\d+)') { Add-Cand $matches[1] }
}

# 2) 从代理 DoH 取最新
try {
    $r = & curl.exe -x http://127.0.0.1:7890 -sS -m 20 `
        "https://1.1.1.1/dns-query?name=cloud.nikke-kr.com&type=A" -H "accept: application/dns-json" 2>$null
    $j = ($r | Out-String) | ConvertFrom-Json
    $j.Answer | Where-Object { $_.type -eq 1 } | ForEach-Object { Add-Cand $_.data }
} catch { }

# 3) 兜底已知 IP
@('108.156.144.59','18.155.173.11','18.155.173.61','18.155.173.65','18.155.173.81') | ForEach-Object { Add-Cand $_ }

if (-not $Quiet) { Write-Host "候选 IP: $($Candidates.Count) 个" -ForegroundColor Cyan }

# 测速（下载前 3MB）
$results = @()
foreach ($ip in $Candidates) {
    if (-not $Quiet) { Write-Host "  测速 $ip ..." -NoNewline }
    $out = & curl.exe --noproxy "*" --resolve "cloud.nikke-kr.com:443:$ip" -sS -m 20 `
        -r 0-3000000 -o NUL -w "%{http_code} %{size_download} %{speed_download}" $TestUrl 2>$null
    $line = ($out | Out-String).Trim()
    $f = $line -split '\s+'
    if ($f.Count -ge 3 -and $f[0] -eq '206') {
        $spd = [int64]$f[2]
        $results += [pscustomobject]@{ IP = $ip; KBps = [math]::Round($spd/1KB, 0) }
        if (-not $Quiet) { Write-Host (" OK {0:N0} KB/s" -f ($spd/1KB)) -ForegroundColor Green }
    } else {
        if (-not $Quiet) { Write-Host ' 失败' -ForegroundColor DarkGray }
    }
}

if ($results.Count -eq 0) {
    Write-Host '所有 IP 都不可用，保持原配置' -ForegroundColor Yellow
    exit 1
}

# 排序
$sorted = $results | Sort-Object KBps -Descending
if (-not $Quiet) {
    Write-Host ''
    Write-Host '测速结果:' -ForegroundColor Cyan
    $sorted | ForEach-Object { Write-Host ("  {0,-16} {1,6:N0} KB/s" -f $_.IP, $_.KBps) }
}

# 写入 hosts
$hl = Get-Content $HostsFile -ErrorAction SilentlyContinue
$filtered = $hl | Where-Object { $_ -notmatch 'cloud\.nikke-kr\.com' -and $_ -notmatch 'EpinelPS: cloud CDN' }
$add = @('', '# EpinelPS: cloud.nikke-kr.com IPs (fastest first, measured)')
foreach ($r in $sorted) { $add += "$($r.IP) cloud.nikke-kr.com" }

Set-Content -Path $HostsFile -Value ($filtered + $add) -Encoding utf8
ipconfig /flushdns | Out-Null

if (-not $Quiet) {
    Write-Host ''
    Write-Host "已更新 hosts（最快: $($sorted[0].IP) @ $($sorted[0].KBps) KB/s）" -ForegroundColor Green
}
