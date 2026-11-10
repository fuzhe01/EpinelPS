<#
.SYNOPSIS
    确保私服 TLS 证书已导入当前用户证书库。

.DESCRIPTION
    EpinelPS 在本机解析 site.pfx 会失败（.NET 10 + 本机 native 库组合下
    PKCS#12 解析报 "指定的网络密码不正确" / "拒绝访问"），但同一文件
    在独立进程和 OpenSSL 中都能正常读取。

    因此服务端改为从 CurrentUser\My 证书库按指纹加载证书。
    本脚本负责把 site.pfx 导入该库，幂等、可重复运行。

.NOTES
    证书指纹: B8C27EB20A0F128BCA489F58A725B445E9CFCEAC
    与 Program.cs 中的 ServerCertThumbprint 常量必须一致。
#>
[CmdletBinding()]
param(
    [string]$PfxPath = "D:\EpinelPS\out\site.pfx",
    [string]$Thumbprint = "B8C27EB20A0F128BCA489F58A725B445E9CFCEAC",
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { if (-not $Quiet) { Write-Host $msg } }

try {
    # 1. 检查库里是否已有
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'CurrentUser')
    $store.Open('ReadOnly')
    $existing = $store.Certificates | Where-Object { $_.Thumbprint -eq $Thumbprint }
    $store.Close()

    if ($existing) {
        Write-Info "  TLS 证书已在 CurrentUser\My ($Thumbprint)"
        exit 0
    }

    # 2. 需要导入
    if (-not (Test-Path $PfxPath)) {
        Write-Error "  找不到 site.pfx: $PfxPath"
        exit 1
    }

    Write-Info "  导入 TLS 证书到 CurrentUser\My ..."
    $imported = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation Cert:\CurrentUser\My
    if (-not $imported) {
        Write-Error "  Import-PfxCertificate 未返回证书"
        exit 1
    }

    $match = $imported | Where-Object { $_.Thumbprint -eq $Thumbprint }
    if (-not $match) {
        Write-Error "  导入的证书指纹不匹配：期望 $Thumbprint，实际 $($imported.Thumbprint -join ', ')"
        exit 1
    }

    Write-Info "  ✓ 导入成功 ($($match.Thumbprint))"
    exit 0
}
catch {
    Write-Error "  证书安装失败: $($_.Exception.Message)"
    exit 1
}