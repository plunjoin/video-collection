# 本地一键打包并按规范命名脚本
# 用法:
#   .\build-release.ps1
#   .\build-release.ps1 -Version v1.0.0
#   .\build-release.ps1 -Target android -Version v1.0.0
#   .\build-release.ps1 -Target windows -Version v1.0.0

param(
    [string]$Version = "v1.0.0",
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"
$AppDir = $PSScriptRoot
$DistDir = Join-Path $AppDir "dist"
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

$ConfigFile = Join-Path $AppDir "env/prod.json"
if (-not (Test-Path $ConfigFile)) {
    Write-Host "[错误] 缺少生产配置文件: $ConfigFile" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Bllii App 本地 Release 打包" -ForegroundColor Cyan
Write-Host "  版本号: $Version" -ForegroundColor Yellow
Write-Host "  目标: $Target" -ForegroundColor Yellow
Write-Host "  配置: env/prod.json" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# 1. 打包 Windows
if ($Target -eq "all" -or $Target -eq "windows") {
    Write-Host ""
    Write-Host "[1/2] 开始构建 Windows 桌面端..." -ForegroundColor Green
    Set-Location $AppDir
    flutter build windows --release --dart-define-from-file=env/prod.json
    
    $winReleaseDir = Join-Path $AppDir "build\windows\x64\runner\Release"
    $winZip = Join-Path $DistDir "bllii_for_windows_${Version}.zip"
    if (Test-Path $winZip) { Remove-Item $winZip -Force }
    
    Write-Host "正在压缩 Windows 绿色包为: bllii_for_windows_${Version}.zip ..." -ForegroundColor Cyan
    Compress-Archive -Path "$winReleaseDir\*" -DestinationPath $winZip -Force
    Write-Host "[完成] Windows: $winZip" -ForegroundColor Green
}

# 2. 打包 Android
if ($Target -eq "all" -or $Target -eq "android") {
    Write-Host ""
    Write-Host "[2/2] 开始构建 Android APK..." -ForegroundColor Green
    Set-Location $AppDir
    flutter build apk --release --dart-define-from-file=env/prod.json
    
    $apkSrc = Join-Path $AppDir "build\app\outputs\flutter-apk\app-release.apk"
    $apkDest = Join-Path $DistDir "bllii_for_android_${Version}.apk"
    
    Copy-Item -Path $apkSrc -Destination $apkDest -Force
    Write-Host "[完成] Android: $apkDest" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  打包产物已归档至: $DistDir" -ForegroundColor Green
Get-ChildItem -Path $DistDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
Write-Host "==========================================" -ForegroundColor Green
