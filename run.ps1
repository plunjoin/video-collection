# 一键启动 video-collection（同一终端并行，Ctrl+C 全部停止）
# 用法: .\run.ps1 admin web windows

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

所有服务在当前终端并行运行，日志带 [api]/[admin]/[web]/[app] 前缀。
按 Ctrl+C 停止全部。

用法:
  .\run.ps1 <目标...>
  .\run.cmd <目标...>
  ./run.sh <目标...>          # macOS / Linux

项目目标:
  api / admin / web / app / all
  Flutter 平台: windows android ios macos linux chrome edge web-server

示例:
  .\run.ps1 admin web windows
  .\run.ps1 api admin web android
  .\run.ps1 all
  .\run.ps1 web

说明:
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
        "node" {
            Write-Host "  缺少 Node.js" -ForegroundColor Red
            Write-Host "  安装: https://nodejs.org/ | winget install OpenJS.NodeJS.LTS" -ForegroundColor Yellow
        }
        "pnpm" {
            Write-Host "  缺少 pnpm" -ForegroundColor Red
            Write-Host "  corepack enable; corepack prepare pnpm@latest --activate" -ForegroundColor Yellow
        }
        "flutter" {
            Write-Host "  缺少 Flutter SDK" -ForegroundColor Red
            Write-Host "  https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
        }
    }
}

function Ensure-Pnpm {
    if (Test-CommandExists "pnpm") { return $true }
    if (-not (Test-CommandExists "node")) { return $false }
    Write-Host "[环境] 未找到 pnpm，尝试 corepack / npm ..." -ForegroundColor Cyan
    if (Test-CommandExists "corepack") {
        try {
            & corepack enable 2>$null | Out-Null
            & corepack prepare pnpm@latest --activate 2>$null | Out-Null
            if (Test-CommandExists "pnpm") {
                Write-Host "[环境] pnpm 已就绪: $(pnpm -v)" -ForegroundColor Green
                return $true
            }
        } catch {}
    }
    if (Test-CommandExists "npm") {
        try {
            & npm install -g pnpm 2>$null | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path", "User")
            if (Test-CommandExists "pnpm") {
                Write-Host "[环境] pnpm 已就绪: $(pnpm -v)" -ForegroundColor Green
                return $true
            }
        } catch {}
    }
    return $false
}

function Ensure-GoDeps {
    $dir = Join-Path $Root "video-collection-api"
    if (-not (Test-Path $dir)) { Write-Host "[跳过] API 目录不存在" -ForegroundColor Yellow; return }
    Write-Host "[依赖] API: go mod download" -ForegroundColor Cyan
    Push-Location $dir
    try { & go mod download } finally { Pop-Location }
}

function Ensure-PnpmDeps {
    param([string]$Name, [string]$Dir)
    if (-not (Test-Path $Dir)) { Write-Host "[跳过] ${Name} 目录不存在" -ForegroundColor Yellow; return }
    if (-not (Test-Path (Join-Path $Dir "node_modules"))) {
        Write-Host "[依赖] ${Name}: pnpm install ..." -ForegroundColor Cyan
        Push-Location $Dir
        try { & pnpm install } finally { Pop-Location }
    } else {
        Write-Host "[依赖] ${Name}: node_modules 已存在，跳过" -ForegroundColor DarkGray
    }
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
            [void]$wantProjects.Add("api")
            [void]$wantProjects.Add("admin")
            [void]$wantProjects.Add("web")
            $wantApp = $true
        }
        "api"   { [void]$wantProjects.Add("api") }
        "admin" { [void]$wantProjects.Add("admin") }
        "web"   { [void]$wantProjects.Add("web") }
        "astro" { [void]$wantProjects.Add("web") }
        "app"   { $wantApp = $true }
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

if ($wantApp -and -not $flutterDevice) {
    if ($IsWindows -or $env:OS -match "Windows") { $flutterDevice = "windows" }
}

if ($wantProjects.Count -eq 0 -and -not $wantApp) {
    Show-Help
    exit 0
}

# ---------- 环境检查 ----------
Write-Host ""
Write-Host "=== video-collection 环境检查 ===" -ForegroundColor Green
$missing = $false
$needNode = $wantProjects.Contains("admin") -or $wantProjects.Contains("web")

if ($wantProjects.Contains("api")) {
    if (Test-CommandExists "go") { Write-Host "[OK] $(go version)" -ForegroundColor Green }
    else { Write-InstallHint "go"; $missing = $true }
}
if ($needNode) {
    if (Test-CommandExists "node") { Write-Host "[OK] node $(node -v)" -ForegroundColor Green }
    else { Write-InstallHint "node"; $missing = $true }
    if (-not $missing) {
        if (Ensure-Pnpm) { Write-Host "[OK] pnpm $(pnpm -v)" -ForegroundColor Green }
        else { Write-InstallHint "pnpm"; $missing = $true }
    }
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

Write-Host ""
Write-Host "=== 检查 / 安装项目依赖 ===" -ForegroundColor Green
if ($wantProjects.Contains("api")) { Ensure-GoDeps }
if ($wantProjects.Contains("admin")) { Ensure-PnpmDeps -Name "Admin" -Dir (Join-Path $Root "video-collection-admin") }
if ($wantProjects.Contains("web")) { Ensure-PnpmDeps -Name "Web" -Dir (Join-Path $Root "video-collection-web") }
if ($wantApp) { Ensure-FlutterDeps }

# ---------- 同一终端启动 ----------
Write-Host ""
Write-Host "=== 启动服务（同一终端） ===" -ForegroundColor Green
$projectList = ($wantProjects | Sort-Object) -join ", "
if (-not $projectList) { $projectList = "(none)" }
$appInfo = if ($wantApp) { "app/$flutterDevice" } else { "(none)" }
Write-Host "projects: $projectList"
Write-Host "app     : $appInfo"
Write-Host ""
Write-Host "日志前缀区分服务。按 Ctrl+C 停止全部。" -ForegroundColor Yellow
Write-Host ""

if ($wantProjects.Contains("api")) {
    Start-ServiceProcess -Tag "api" -WorkDir (Join-Path $Root "video-collection-api") -Command "go run ." -Color Green
}
if ($wantProjects.Contains("admin")) {
    Start-ServiceProcess -Tag "admin" -WorkDir (Join-Path $Root "video-collection-admin") -Command "pnpm dev" -Color Magenta
}
if ($wantProjects.Contains("web")) {
    Start-ServiceProcess -Tag "web" -WorkDir (Join-Path $Root "video-collection-web") -Command "pnpm start" -Color Cyan
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