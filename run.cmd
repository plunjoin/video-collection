@echo off
REM Windows 入口：先切 UTF-8，再转发到 run.ps1
REM macOS / Linux 请使用: chmod +x run.sh && ./run.sh ...
setlocal
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
set PYTHONUTF8=1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
