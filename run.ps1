# 一键启动 video-collection（同一终端并行，Ctrl+C 全部停止）
# 用法: .\run.ps1 service web windows

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Targets
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

# ---------- 控制台 UTF-8（解决中文乱码）----------
function Initialize-ConsoleUtf8 {
    try { $null = cmd.exe /c "chcp 65001 >nul 2>nul" } catch {}
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [Console]::InputEncoding  = $utf8
        [Console]::OutputEncoding = $utf8
        $global:OutputEncoding    = $utf8
        $PSDefaultParameterValues['*:Encoding'] = 'utf8'
        $env:PYTHONIOENCODING = "utf-8"
        $env:PYTHONUTF8 = "1"
    } catch {}
}
Initialize-ConsoleUtf8

$FlutterDevices = @{
    windows      = "windows"
    android      = "android"
    ios          = "ios"
    macos        = "macos"
    linux        = "linux"
    chrome       = "chrome"
    edge         = "edge"
    "web-server" = "web-server"
}

function Show-Help {
    @"
一键启动 video-collection 子项目

所有服务在当前终端并行运行，日志带 [service]/[web]/[app] 前缀。
按 Ctrl+C 停止全部。

用法:
  .\run.ps1 <目标...>
  ./run.sh <目标...>          # macOS / Linux

项目目标:
  service / admin / web / app / all
  （api 为 service 的别名）
  service  统一服务：/ 门户（webfront 托管）+ /admin 管理后台（内嵌产物）+ /api
  admin    先用 wf 构建管理后台（webfront CLI，零 Node）打进二进制，再启动统一服务在 /admin 查看
  web      以开发模式启动统一服务（go run -tags dev .）：门户与管理后台都挂
           webfront DevServer（HMR）；与 service 同时选择时只启动一个进程（无 HMR）
  Flutter 平台: windows android ios macos linux chrome edge web-server

示例:
  .\run.ps1 service
  .\run.ps1 admin              # 构建管理后台并启动服务
  .\run.ps1 web                # 门户开发模式（HMR）
  .\run.ps1 api web android    # api 等同于 service
  .\run.ps1 all

说明:
  - 前端构建统一走 webfront wf CLI（纯 Go），本脚本不依赖 Node
  - 缺少运行时会提示安装方式并退出
  - 缺少项目依赖会自动安装
  - 脚本会自动切换控制台为 UTF-8，避免中文乱码
"@ | Write-Host
}

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Write-InstallHint {
    param([string]$Tool)
    switch ($Tool) {
        "go" {
            Write-Host "  缺少 Go" -ForegroundColor Red
            Write-Host "  安装: https://go.dev/dl/ | winget install GoLang.Go" -ForegroundColor Yellow
        }
        "wf" {
            Write-Host "  缺少 webfront wf CLI" -ForegroundColor Red
            Write-Host "  安装: go install github.com/plunjoin/webfront/cmd/wf@v0.1.0" -ForegroundColor Yellow
            Write-Host "  （仓库根已自带 wf.exe / wf.ps1，启动器会优先使用）" -ForegroundColor Yellow
        }
        "flutter" {
            Write-Host "  缺少 Flutter SDK" -ForegroundColor Red
            Write-Host "  https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
        }
    }
}

# wf 解析顺序：仓库根 wf.exe（wf.ps1 同目录包装）→ PATH
function Get-WfCommand {
    $local = Join-Path $Root "wf.exe"
    if (Test-Path $local) { return $local }
    if (Test-CommandExists "wf") { return "wf" }
    return $null
}

function Ensure-GoDeps {
    param([string]$Dir)
    if (-not $Dir) { $Dir = Join-Path $Root "video-collection-service" }
    if (-not (Test-Path $Dir)) { Write-Host "[跳过] Service 目录不存在" -ForegroundColor Yellow; return }
    Write-Host "[依赖] Service: go mod download" -ForegroundColor Cyan
    Push-Location $Dir
    try { & go mod download } finally { Pop-Location }
}

function Ensure-WfDeps {
    param([string]$Wf)
    $serviceDir = Join-Path $Root "video-collection-service"
    $store = Join-Path $serviceDir "web/wf_modules/.store/manifest.json"
    if (Test-Path $store) {
        Write-Host "[依赖] 前端: wf_modules 已存在，跳过" -ForegroundColor DarkGray
        return
    }
    Write-Host "[依赖] 前端: wf install（零 Node，按 web/package-lock.json 锁定版本）..." -ForegroundColor Cyan
    Push-Location $serviceDir
    try { & $Wf install -modules wf_modules . } finally { Pop-Location }
}

function Build-AdminFrontend {
    param([string]$Wf)
    $serviceDir = Join-Path $Root "video-collection-service"
    Write-Host "[构建] 管理后台: wf build（esbuild，秒级）..." -ForegroundColor Cyan
    Push-Location $serviceDir
    try {
        & $Wf build -mode spa -base /admin -modules ../wf_modules web/admin
        if ($LASTEXITCODE -ne 0) { throw "wf build admin 失败" }
    } finally { Pop-Location }
}

function Build-PortalFrontend {
    param([string]$Wf)
    $serviceDir = Join-Path $Root "video-collection-service"
    Write-Host "[构建] 门户: wf build（SSR bundle + 分包）..." -ForegroundColor Cyan
    Push-Location $serviceDir
    try {
        & $Wf build -modules ../wf_modules web/portal
        if ($LASTEXITCODE -ne 0) { throw "wf build portal 失败" }
    } finally { Pop-Location }
}

function Ensure-FlutterDeps {
    $dir = Join-Path $Root "video-collection-app"
    if (-not (Test-Path $dir)) { Write-Host "[跳过] App 目录不存在" -ForegroundColor Yellow; return }
    Write-Host "[依赖] App: flutter pub get" -ForegroundColor Cyan
    Push-Location $dir
    try { & flutter pub get } finally { Pop-Location }
}

function Stop-ProcessTree {
    param([int]$ProcessId)
    try {
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-ProcessTree -ProcessId $_.ProcessId }
    } catch {}
    try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}

# 线程安全日志队列 + UTF-8 重定向子进程
$script:LogQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
$script:Services = [System.Collections.Generic.List[object]]::new()
$script:EventSubs = [System.Collections.Generic.List[object]]::new()

function Start-ServiceProcess {
    param(
        [string]$Tag,
        [string]$WorkDir,
        [string]$Command,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    if (-not (Test-Path $WorkDir)) {
        Write-Host "[跳过] ${Tag} — 目录不存在: $WorkDir" -ForegroundColor Yellow
        return
    }

    Write-Host "[启动] ${Tag}" -ForegroundColor $Color
    Write-Host "       $Command" -ForegroundColor DarkGray

    $utf8 = New-Object System.Text.UTF8Encoding $false
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    # 先切 UTF-8 代码页，再执行业务命令
    $psi.Arguments = "/d /c chcp 65001>nul & $Command"
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8"
    $psi.EnvironmentVariables["PYTHONUTF8"] = "1"

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true

    $msg = @{ Tag = $Tag; Color = $Color; Queue = $script:LogQueue }
    $handler = {
        if ($null -ne $EventArgs.Data) {
            $Event.MessageData.Queue.Enqueue(@{
                Tag   = $Event.MessageData.Tag
                Color = $Event.MessageData.Color
                Line  = $EventArgs.Data
            })
        }
    }

    $subOut = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $handler -MessageData $msg
    $subErr = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $handler -MessageData $msg
    $script:EventSubs.Add($subOut) | Out-Null
    $script:EventSubs.Add($subErr) | Out-Null

    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    $script:Services.Add([pscustomobject]@{
        Tag   = $Tag
        Color = $Color
        Proc  = $proc
    }) | Out-Null
}

function Stop-AllServices {
    foreach ($item in @($script:Services)) {
        if ($null -ne $item.Proc -and -not $item.Proc.HasExited) {
            Stop-ProcessTree -ProcessId $item.Proc.Id
        }
    }
    foreach ($sub in @($script:EventSubs)) {
        try { Unregister-Event -SourceIdentifier $sub.Name -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job $sub -Force -ErrorAction SilentlyContinue } catch {}
    }
    $script:EventSubs.Clear()
    $script:Services.Clear()
}

function Write-QueuedLogs {
    $item = $null
    while ($script:LogQueue.TryDequeue([ref]$item)) {
        Write-Host ("[{0}] {1}" -f $item.Tag, $item.Line) -ForegroundColor $item.Color
    }
}

# ---------- 解析参数 ----------
if (-not $Targets -or $Targets.Count -eq 0 -or $Targets -contains "help" -or $Targets -contains "-h" -or $Targets -contains "--help") {
    Show-Help
    exit 0
}

$normalized = $Targets | ForEach-Object { $_.ToLowerInvariant().Trim() }
$wantProjects = [System.Collections.Generic.HashSet[string]]::new()
$flutterDevice = $null
$wantApp = $false

foreach ($token in $normalized) {
    switch ($token) {
        "all" {
            [void]$wantProjects.Add("service")
            [void]$wantProjects.Add("admin")
            [void]$wantProjects.Add("web")
            $wantApp = $true
        }
        "api"     { [void]$wantProjects.Add("service") }
        "service" { [void]$wantProjects.Add("service") }
        "admin"   { [void]$wantProjects.Add("admin") }
        "web"     { [void]$wantProjects.Add("web") }
        "app"     { $wantApp = $true }
        default {
            if ($FlutterDevices.ContainsKey($token)) {
                $flutterDevice = $FlutterDevices[$token]
                $wantApp = $true
            } else {
                Write-Host "[错误] 未知目标: $token" -ForegroundColor Red
                Write-Host "运行 .\run.ps1 help 查看用法" -ForegroundColor Yellow
                exit 1
            }
        }
    }
}

# admin / web 都是"启动统一服务"的不同形态：
#   admin → 先 wf 构建管理后台，再启动服务（内嵌）
#   web   → 开发模式启动（go run -tags dev .，门户 HMR）；选了 service 时让位
$needService = $wantProjects.Contains("service") -or $wantProjects.Contains("admin") -or $wantProjects.Contains("web")
$buildAdmin  = $wantProjects.Contains("admin")
$buildPortal = $normalized -contains "all"
$devMode     = -not $wantProjects.Contains("service") -and $wantProjects.Contains("web")

if ($wantApp -and -not $flutterDevice) {
    if ($IsWindows -or $env:OS -match "Windows") { $flutterDevice = "windows" }
}

if (-not $needService -and -not $wantApp) {
    Show-Help
    exit 0
}

# ---------- 环境检查 ----------
Write-Host ""
Write-Host "=== video-collection 环境检查 ===" -ForegroundColor Green
$missing = $false

if ($needService) {
    if (Test-CommandExists "go") { Write-Host "[OK] $(go version)" -ForegroundColor Green }
    else { Write-InstallHint "go"; $missing = $true }

    $wfCmd = Get-WfCommand
    if ($wfCmd) { Write-Host "[OK] wf CLI: $wfCmd" -ForegroundColor Green }
    else { Write-InstallHint "wf"; $missing = $true }
    $script:WfCmd = $wfCmd
}
if ($wantApp) {
    if (Test-CommandExists "flutter") {
        Write-Host "[OK] $((flutter --version | Select-Object -First 1))" -ForegroundColor Green
    } else { Write-InstallHint "flutter"; $missing = $true }
}
if ($missing) {
    Write-Host ""; Write-Host "[中止] 请先安装缺失的运行环境后再重试。" -ForegroundColor Red
    exit 1
}

# ---------- 检查 / 安装项目依赖 ----------
Write-Host ""
Write-Host "=== 检查 / 安装项目依赖 ===" -ForegroundColor Green
if ($needService) {
    Ensure-GoDeps -Dir (Join-Path $Root "video-collection-service")
    Ensure-WfDeps -Wf $script:WfCmd
}
if ($buildAdmin)  { Build-AdminFrontend -Wf $script:WfCmd }
if ($buildPortal) { Build-PortalFrontend -Wf $script:WfCmd }
if ($wantApp)     { Ensure-FlutterDeps }

# ---------- 同一终端启动 ----------
Write-Host ""
Write-Host "=== 启动服务（同一终端） ===" -ForegroundColor Green
$appInfo = if ($wantApp) { "app/$flutterDevice" } else { "(none)" }
Write-Host "app     : $appInfo"
Write-Host ""
Write-Host "日志前缀区分服务。按 Ctrl+C 停止全部。" -ForegroundColor Yellow
Write-Host ""

if ($needService) {
    $runCmd = "go run ."
    $tag    = "service"
    if ($devMode) {
        $runCmd = "go run -tags dev ."
        $tag    = "web"
        Write-Host "[web] 门户与管理后台均挂 webfront DevServer（HMR）" -ForegroundColor Cyan
    } elseif ($wantProjects.Contains("web")) {
        Write-Host "[web] 与 service 同进程，门户走内嵌产物；需要 HMR 请单选 web" -ForegroundColor DarkGray
    }
    Start-ServiceProcess -Tag $tag -WorkDir (Join-Path $Root "video-collection-service") -Command $runCmd -Color Green
}
if ($wantApp) {
    $cmd = if ($flutterDevice) { "flutter run -d $flutterDevice" } else { "flutter run" }
    Start-ServiceProcess -Tag "app" -WorkDir (Join-Path $Root "video-collection-app") -Command $cmd -Color Yellow
}

if ($script:Services.Count -eq 0) {
    Write-Host "[中止] 没有可启动的服务" -ForegroundColor Red
    exit 1
}

try {
    while ($true) {
        Write-QueuedLogs
        $anyRunning = $false
        foreach ($item in @($script:Services)) {
            if (-not $item.Proc.HasExited) { $anyRunning = $true }
        }
        if (-not $anyRunning) {
            Start-Sleep -Milliseconds 200
            Write-QueuedLogs
            break
        }
        Start-Sleep -Milliseconds 80
    }
    Write-Host ""
    Write-Host "全部服务已结束。" -ForegroundColor Green
}
finally {
    Write-Host ""
    Write-Host "正在停止全部服务..." -ForegroundColor Yellow
    Write-QueuedLogs
    Stop-AllServices
    Write-Host "已全部停止。" -ForegroundColor Green
}
