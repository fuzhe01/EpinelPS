# 检查 EpinelPS 服务端更新（仅 GitHub）
# Token 来源优先级：
#   1) -Token 参数
#   2) 环境变量 GITHUB_TOKEN / GH_TOKEN
#   3) 文件 D:\EpinelPS\github-token.txt（仅本机，注意保密）
param(
    [string]$Token,
    [switch]$Json
)

$ErrorActionPreference = 'Continue'

$Repo        = 'AzureXuanDust/Depot'
$RepoUrl     = "https://github.com/$Repo"
$ReleaseBase = "$RepoUrl/releases/download"
$TokenFile   = 'D:\EpinelPS\github-token.txt'

# ---------- 解析 token ----------
function Resolve-Token {
    if ($Token) { return $Token.Trim() }
    foreach ($n in @('GITHUB_TOKEN','GH_TOKEN','GITHUB_PAT')) {
        $v = [Environment]::GetEnvironmentVariable($n, 'Process')
        if (-not $v) { $v = [Environment]::GetEnvironmentVariable($n, 'User') }
        if ($v) { return $v.Trim() }
    }
    if (Test-Path $TokenFile) {
        $v = (Get-Content $TokenFile -Raw -ErrorAction SilentlyContinue)
        if ($v) { return $v.Trim() }
    }
    return $null
}

$tk = Resolve-Token

function New-GitHubHeaders {
    $h = @{
        'User-Agent' = 'EpinelPS-UpdateChecker'
        'Accept'     = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    if ($tk) { $h['Authorization'] = "Bearer $tk" }
    return $h
}

# ---------- GitHub API ----------
function Try-GitHubApi {
    try {
        $hdr = New-GitHubHeaders
        $r = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases?per_page=20" -TimeoutSec 30 -Headers $hdr
        $rel = $r | Where-Object { $_.tag_name -like 'epinelps-*' } | Select-Object -First 1
        if (-not $rel) { return $null }

        $asset = $rel.assets | Where-Object { $_.name -like '*windows*x86_64*' } | Select-Object -First 1
        $sha = $null
        if ($asset -and $asset.digest) { $sha = $asset.digest -replace '^sha256:','' }

        return [pscustomobject]@{
            Source  = if ($tk) { 'GitHub API (已认证)' } else { 'GitHub API' }
            Version = $rel.tag_name -replace '^epinelps-v',''
            Tag     = $rel.tag_name
            Url     = if ($asset) { $asset.browser_download_url } else { $null }
            Asset   = if ($asset) { $asset.name } else { $null }
            Size    = if ($asset) { $asset.size } else { 0 }
            Sha256  = $sha
            Notes   = if ($rel.body) { $rel.body.Substring(0, [Math]::Min(300, $rel.body.Length)) } else { '' }
        }
    } catch {
        $code = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        Write-Verbose "GitHub API 失败 (HTTP $code): $($_.Exception.Message)"
        return $null
    }
}

# ---------- GitHub 页面回退（无需 token） ----------
function Try-GitHubPage {
    try {
        $page = Invoke-WebRequest "$RepoUrl/releases" -TimeoutSec 30 -UseBasicParsing -Headers @{'User-Agent'='Mozilla/5.0'}
        $m = [regex]::Matches($page.Content, "/$Repo/releases/tag/(epinelps-v[^`"'<>\s]+)") |
             ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique -First 1
        if (-not $m) { return $null }

        $ver = $m -replace '^epinelps-v',''
        return [pscustomobject]@{
            Source  = 'GitHub 页面（无需 token）'
            Version = $ver
            Tag     = $m
            Url     = "$ReleaseBase/$m/EpinelPS-v$ver-windows-x86_64.tar.gz"
            Asset   = "EpinelPS-v$ver-windows-x86_64.tar.gz"
            Size    = 0
            Sha256  = $null
            Notes   = ''
        }
    } catch {
        Write-Verbose "GitHub 页面失败: $($_.Exception.Message)"
        return $null
    }
}

# ---------- 主流程 ----------
$result = Try-GitHubApi
if (-not $result) {
    if (-not $Json) { Write-Host 'GitHub API 不可用，回退到页面解析...' -ForegroundColor Yellow }
    $result = Try-GitHubPage
}

if (-not $result) {
    if ($Json) { '{"error":"github unreachable"}' }
    else { Write-Host 'GitHub 更新源不可用' -ForegroundColor Red }
    exit 1
}

# 补齐大小（HEAD 请求）
if ($result.Url -and $result.Size -eq 0) {
    try {
        $h = Invoke-WebRequest $result.Url -Method Head -TimeoutSec 25 -UseBasicParsing -Headers @{'User-Agent'='Mozilla/5.0'}
        $len = $h.Headers['Content-Length']
        if ($len -is [array]) { $len = $len[0] }
        if ($len) { $result.Size = [int64]$len }
    } catch { Write-Verbose "HEAD 失败: $_" }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 3
} else {
    Write-Host "更新源 : $($result.Source)" -ForegroundColor Cyan
    Write-Host "版本   : $($result.Version)"
    Write-Host "Tag    : $($result.Tag)"
    if ($result.Asset)  { Write-Host "文件   : $($result.Asset)" }
    if ($result.Size)   { Write-Host ("大小   : {0:N1} MB" -f ($result.Size/1MB)) }
    if ($result.Sha256) { Write-Host "SHA256 : $($result.Sha256.Substring(0,16))..." }
    if ($result.Url)    { Write-Host "下载   : $($result.Url)" }
    if ($result.Notes)  { Write-Host "说明   : $($result.Notes -replace "`n", ' ')" }
}

return $result
