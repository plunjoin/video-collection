#requires -Version 5.1
<#
  Build the Bllii Windows installer.

  Steps:
    1. flutter build windows --release (skip with -SkipFlutter)
    2. zip the Release folder into payload.zip
    3. publish the uninstaller stub (BlliiUninstall.exe)
    4. publish the installer (BlliiSetup.exe with embedded payload + stub) into dist/

  Usage:
    powershell -ExecutionPolicy Bypass -File installer\app\build.ps1
    powershell -ExecutionPolicy Bypass -File installer\app\build.ps1 -SkipFlutter -Version v1.0.2
#>
param(
    [string]$Version = "v1.0.1",
    [string]$EnvFile = "env/dev.json",
    [switch]$SkipFlutter
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = (Resolve-Path (Join-Path $here "..\..")).Path
$project = Join-Path $here "BlliiSetup"
$buildDir = Join-Path $project ".build"
$releaseDir = Join-Path $appRoot "build\windows\x64\runner\Release"
$distDir = Join-Path $appRoot "dist"

function Write-Step($message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

if (-not $SkipFlutter) {
    Write-Step "flutter build windows --release"
    Push-Location $appRoot
    try {
        flutter build windows --release --dart-define-from-file=$EnvFile
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
    }
    finally { Pop-Location }
}

if (-not (Test-Path $releaseDir)) { throw "Windows build not found: $releaseDir" }

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $buildDir "stub") | Out-Null
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

Write-Step "Packing payload"
$payload = Join-Path $buildDir "payload.zip"
if (Test-Path $payload) { Remove-Item $payload -Force }

$zipScript = @'
param([string]$Source, [string]$Target)
# Compress-Archive is a cmdlet so it works on every Windows PowerShell 5.1 host
Compress-Archive -Path (Join-Path $Source '*') -DestinationPath $Target -CompressionLevel Optimal -Force
'@
$zipScriptPath = Join-Path $buildDir "zip.ps1"
Set-Content -Path $zipScriptPath -Value $zipScript -Encoding UTF8
& powershell -NoProfile -ExecutionPolicy Bypass -File $zipScriptPath -Source $releaseDir -Target $payload
if (-not (Test-Path $payload)) { throw "payload.zip was not created" }
Write-Host ("    payload.zip {0:N1} MB" -f ((Get-Item $payload).Length / 1MB))

Write-Step "Publishing uninstaller"
$stubPublish = Join-Path $buildDir "stub-publish"
if (Test-Path $stubPublish) { Remove-Item $stubPublish -Recurse -Force }
dotnet publish $project -c Release -p:BlliiUninstaller=true -o $stubPublish --nologo -v q
if ($LASTEXITCODE -ne 0) { throw "uninstaller publish failed" }
Copy-Item (Join-Path $stubPublish "BlliiUninstall.exe") (Join-Path $buildDir "stub\BlliiUninstall.exe") -Force

Write-Step "Publishing installer"
$setupPublish = Join-Path $buildDir "setup-publish"
if (Test-Path $setupPublish) { Remove-Item $setupPublish -Recurse -Force }
dotnet publish $project -c Release -o $setupPublish --nologo -v q
if ($LASTEXITCODE -ne 0) { throw "installer publish failed" }

$output = Join-Path $distDir "bllii_setup_windows_$Version.exe"
Copy-Item (Join-Path $setupPublish "BlliiSetup.exe") $output -Force

Write-Step "Done"
Get-Item $output | ForEach-Object { Write-Host ("    {0}  {1:N1} MB" -f $_.FullName, ($_.Length / 1MB)) }
