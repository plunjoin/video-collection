#Requires -Version 5.1
<#
.SYNOPSIS
    Bllii Windows 发布产物代码签名 (Authenticode)
.DESCRIPTION
    支持三类签名凭据 (按优先级自动探测):
      1. PFX 文件        -PfxPath / -PfxPassword, 或环境变量 BLLII_CERT_PFX / BLLII_CERT_PASSWORD
      2. 证书存储区指纹  -Thumbprint, 或环境变量 BLLII_CERT_THUMBPRINT
                          (依次在 CurrentUser\My、LocalMachine\My 中查找)
      3. Azure 受信任签名 -DlibPath / -DmdfPath, 或环境变量 BLLII_AZURE_DLIB / BLLII_AZURE_DMDF
                          (Azure 侧认证走 AZURE_CLIENT_ID / AZURE_CLIENT_SECRET / AZURE_TENANT_ID)

    未配置任何凭据时默认跳过签名并以退出码 0 结束, 方便本地或无证书环境继续构建;
    加 -RequireSignature 则改为失败退出, 适用于正式发布流水线。

    签名对象可以是: 单个 PE 文件、整个目录 (递归签名 *.exe / *.dll)、.zip 压缩包
    (自动解压 -> 签名 -> 重新打包, 解决"先打包后签名"的顺序问题)。

    详细说明见 installer/SIGNING.md
.PARAMETER Path
    待签名的文件 / 目录 / .zip 压缩包
.PARAMETER TimestampUrl
    RFC3161 时间戳服务器, 默认 http://timestamp.digicert.com
    (Azure 模式默认使用 http://timestamp.acs.microsoft.com)
.PARAMETER RequireSignature
    未配置签名凭据时以非零退出码失败, 而不是跳过
.EXAMPLE
    .\sign-release.ps1 -Path build\windows\x64\runner\Release
.EXAMPLE
    .\sign-release.ps1 -Path dist\bllii_setup_windows_v1.0.1.exe
.EXAMPLE
    $env:BLLII_CERT_PFX = "C:\certs\bllii.pfx"
    $env:BLLII_CERT_PASSWORD = "your-password"
    .\sign-release.ps1 -Path dist\bllii_for_windows_v1.0.1.zip
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,

    [string]$TimestampUrl = "http://timestamp.digicert.com",

    [string]$PfxPath,
    [string]$PfxPassword,
    [string]$Thumbprint,
    [string]$DlibPath,
    [string]$DmdfPath,

    [switch]$RequireSignature
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------ 定位 signtool

function Get-SignToolPath {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # 未加入 PATH 时, 遍历 Windows SDK 安装目录, 取最高版本
    $kitRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (Test-Path $kitRoot) {
        $versions = Get-ChildItem -Path $kitRoot -Directory |
            Where-Object { $_.Name -match '^\d+(\.\d+){3}$' } |
            Sort-Object { [Version]$_.Name } -Descending
        foreach ($v in $versions) {
            foreach ($arch in @("x64", "x86")) {
                $candidate = Join-Path $kitRoot "$($v.Name)\$arch\signtool.exe"
                if (Test-Path $candidate) { return $candidate }
            }
        }
    }
    return $null
}

# ------------------------------------------------------------------ 凭据解析

function Get-CertificateFromStore {
    param([string]$CertThumbprint)
    foreach ($location in @("CurrentUser", "LocalMachine")) {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store(
            "My", $location)
        try {
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
            $certs = $store.Certificates.Find(
                [System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint,
                $CertThumbprint, $false)
            if ($certs.Count -gt 0) {
                return @{ Cert = $certs[0]; Location = $location }
            }
        } finally {
            $store.Close()
        }
    }
    return $null
}

function Get-SigningCredential {
    <#
      返回 hashtable:
        @{ Mode = 'pfx';   PfxPath; PfxPassword }
        @{ Mode = 'store'; Thumbprint; StoreLocation }
        @{ Mode = 'azure'; DlibPath; DmdfPath }
      未找到任何凭据时返回 $null
    #>
    if (-not $PfxPath -and $env:BLLII_CERT_PFX)          { $PfxPath = $env:BLLII_CERT_PFX }
    if (-not $PfxPassword -and $env:BLLII_CERT_PASSWORD) { $PfxPassword = $env:BLLII_CERT_PASSWORD }
    if (-not $Thumbprint -and $env:BLLII_CERT_THUMBPRINT) { $Thumbprint = $env:BLLII_CERT_THUMBPRINT }
    if (-not $DlibPath -and $env:BLLII_AZURE_DLIB)       { $DlibPath = $env:BLLII_AZURE_DLIB }
    if (-not $DmdfPath -and $env:BLLII_AZURE_DMDF)       { $DmdfPath = $env:BLLII_AZURE_DMDF }

    if ($PfxPath) {
        if (-not (Test-Path $PfxPath)) {
            throw "PFX 证书文件不存在: $PfxPath"
        }
        if (-not $PfxPassword) {
            if (-not [Environment]::UserInteractive) {
                # CI 等非交互环境不允许弹提示, 直接失败, 避免挂起
                throw "PFX 证书密码未提供: 请设置环境变量 BLLII_CERT_PASSWORD 或使用 -PfxPassword 参数"
            }
            $secure = Read-Host -AsSecureString -Prompt "请输入 PFX 证书密码 ($PfxPath)"
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try {
                $PfxPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        return @{ Mode = "pfx"; PfxPath = $PfxPath; PfxPassword = $PfxPassword }
    }

    if ($Thumbprint) {
        $clean = ($Thumbprint -replace '\s', '').ToUpper()
        $found = Get-CertificateFromStore -CertThumbprint $clean
        if (-not $found) {
            throw "在证书存储区 (CurrentUser\My / LocalMachine\My) 中找不到指纹为 $clean 的证书"
        }
        return @{ Mode = "store"; Thumbprint = $clean; StoreLocation = $found.Location }
    }

    if ($DlibPath -or $DmdfPath) {
        if (-not $DlibPath -or -not $DmdfPath) {
            throw "Azure 受信任签名模式需要同时提供 -DlibPath (Azure.CodeSigning.dll) 和 -DmdfPath (metadata.json)"
        }
        if (-not (Test-Path $DlibPath)) { throw "Azure 签名库不存在: $DlibPath" }
        if (-not (Test-Path $DmdfPath)) { throw "Azure 签名元数据不存在: $DmdfPath" }
        return @{ Mode = "azure"; DlibPath = $DlibPath; DmdfPath = $DmdfPath }
    }

    return $null
}

# ------------------------------------------------------------------ 单文件签名

function Invoke-SignFile {
    param(
        [string]$SignTool,
        [string]$File,
        $Credential,
        [string]$Timestamp
    )

    $signArgs = @("sign", "/fd", "SHA256", "/v")

    switch ($Credential.Mode) {
        "pfx" {
            $signArgs += @("/f", $Credential.PfxPath, "/p", $Credential.PfxPassword)
        }
        "store" {
            if ($Credential.StoreLocation -eq "LocalMachine") { $signArgs += "/sm" }
            $signArgs += @("/s", "My", "/sha1", $Credential.Thumbprint)
        }
        "azure" {
            $signArgs += @("/dlib", $Credential.DlibPath, "/dmdf", $Credential.DmdfPath)
        }
    }

    if ($Timestamp) {
        # RFC3161 时间戳: 证书过期后已签名文件仍显示有效
        $signArgs += @("/tr", $Timestamp, "/td", "SHA256")
    }

    $signArgs += $File

    & $SignTool @signArgs
    if ($LASTEXITCODE -ne 0) {
        throw "signtool 签名失败 (退出码 $LASTEXITCODE): $File"
    }

    # 签名后校验, 防止"静默失败"留下未签名产物
    & $SignTool verify /pa /q $File
    if ($LASTEXITCODE -ne 0) {
        throw "签名验证失败: $File"
    }
}

# ------------------------------------------------------------------ 主流程

$resolved = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
if (-not $resolved) { throw "路径不存在: $Path" }
$resolved = $resolved.Path

$signTool = Get-SignToolPath
if (-not $signTool) {
    throw "未找到 signtool.exe, 请安装 Windows SDK: https://developer.microsoft.com/windows/downloads/windows-sdk/"
}
Write-Host "[签名] 使用 signtool: $signTool" -ForegroundColor DarkCyan

$credential = Get-SigningCredential
if (-not $credential) {
    if ($RequireSignature) {
        Write-Error "未配置任何签名凭据 (PFX / 证书存储区指纹 / Azure Trusted Signing), 且指定了 -RequireSignature"
        exit 1
    }
    Write-Warning "未配置签名凭据, 跳过代码签名 (配置方法见 installer/SIGNING.md)"
    exit 0
}

# Azure 受信任签名默认使用自己的时间戳服务
$timestamp = $TimestampUrl
if ($credential.Mode -eq "azure" -and $TimestampUrl -eq "http://timestamp.digicert.com") {
    $timestamp = "http://timestamp.acs.microsoft.com"
}
Write-Host "[签名] 凭据模式: $($credential.Mode) | 时间戳: $timestamp" -ForegroundColor DarkCyan

$script:signedCount = 0
$script:failedFiles = @()

function Sign-Tree {
    param([string]$Root)
    $files = Get-ChildItem -Path $Root -Recurse -Include *.exe, *.dll | Sort-Object FullName
    if (-not $files) {
        Write-Warning "目录中未找到可签名的 PE 文件 (*.exe / *.dll): $Root"
        return
    }
    foreach ($f in $files) {
        try {
            Invoke-SignFile -SignTool $script:signTool -File $f.FullName -Credential $script:credential -Timestamp $script:timestamp
            $script:signedCount++
            Write-Host "  [OK] $($f.FullName)" -ForegroundColor Green
        } catch {
            $script:failedFiles += $f.FullName
            Write-Warning "签名失败: $($f.FullName) - $($_.Exception.Message)"
        }
    }
}

if (Test-Path -LiteralPath $resolved -PathType Container) {
    # 目录: 递归签名所有 exe / dll
    Sign-Tree -Root $resolved
}
elseif ($resolved -like "*.zip") {
    # zip 包: 解压 -> 签名 -> 重新打包
    $tempDir = Join-Path $env:TEMP ("bllii-sign-" + [Guid]::NewGuid().ToString("N"))
    try {
        Write-Host "[签名] 解压 zip 到临时目录: $tempDir" -ForegroundColor DarkCyan
        Expand-Archive -LiteralPath $resolved -DestinationPath $tempDir -Force
        Sign-Tree -Root $tempDir

        Remove-Item -LiteralPath $resolved -Force
        Compress-Archive -Path "$tempDir\*" -DestinationPath $resolved -Force
        Write-Host "[签名] 已重新打包: $resolved" -ForegroundColor DarkCyan
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    # 单个文件: 直接签名
    try {
        Invoke-SignFile -SignTool $signTool -File $resolved -Credential $credential -Timestamp $timestamp
        $script:signedCount++
        Write-Host "  [OK] $resolved" -ForegroundColor Green
    } catch {
        $script:failedFiles += $resolved
        Write-Warning "签名失败: $resolved - $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  签名完成: $script:signedCount 个文件" -ForegroundColor Cyan
if ($script:failedFiles.Count -gt 0) {
    Write-Host "  失败: $($script:failedFiles.Count) 个文件" -ForegroundColor Red
    foreach ($f in $script:failedFiles) { Write-Host "    - $f" -ForegroundColor Red }
    exit 1
}
Write-Host "==========================================" -ForegroundColor Cyan
exit 0
