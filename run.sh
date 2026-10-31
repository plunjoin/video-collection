#!/usr/bin/env bash
# 一键启动 video-collection（同一终端并行，Ctrl+C 全部停止）
# 用法: ./run.sh service web macos

set -euo pipefail

# UTF-8 locale，避免中文乱码
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export PYTHONUTF8="${PYTHONUTF8:-1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_CYN=$'\033[36m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_CYN=; C_DIM=; C_RST=
fi

info()  { printf '%s%s%s\n' "$C_CYN" "$*" "$C_RST"; }
ok()    { printf '%s%s%s\n' "$C_GRN" "$*" "$C_RST"; }
warn()  { printf '%s%s%s\n' "$C_YEL" "$*" "$C_RST"; }
err()   { printf '%s%s%s\n' "$C_RED" "$*" "$C_RST" >&2; }
dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RST"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

show_help() {
  cat <<'EOF'
一键启动 video-collection 子项目（macOS / Linux）

所有服务在当前终端并行运行，日志带 [service]/[web]/[app] 前缀。
按 Ctrl+C 停止全部。

用法:
  ./run.sh <目标...>
  ./run.sh help

项目目标:
  service / admin / web / app / all
  （api 为 service 的别名）
  service  统一服务：/ 门户（webfront 托管）+ /admin 管理后台（内嵌产物）+ /api
  admin    先用 wf 构建管理后台（webfront CLI，零 Node）打进二进制，再启动统一服务在 /admin 查看
  web      以开发模式启动统一服务（go run -tags dev .）：门户与管理后台都挂
           webfront DevServer（HMR）；与 service 同时选择时只启动一个进程（无 HMR）
  Flutter 平台: windows android ios macos linux chrome edge web-server

示例:
  ./run.sh service
  ./run.sh admin
  ./run.sh web
  ./run.sh api web android
  ./run.sh all

说明:
  - 前端构建统一走 webfront wf CLI（纯 Go），本脚本不依赖 Node
  - 缺少运行时会提示安装方式并退出
  - 缺少项目依赖会自动安装
  - 自动使用 UTF-8 locale，避免中文乱码
  - Windows 请使用 run.ps1
EOF
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "help" ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

WANT_ADMIN=0
WANT_SERVICE=0
WANT_WEB=0
WANT_APP=0
WANT_ALL=0
FLUTTER_DEVICE=""

is_flutter_device() {
  case "$1" in
    windows|android|ios|macos|linux|chrome|edge|web-server) return 0 ;;
    *) return 1 ;;
  esac
}

for token in "$@"; do
  t="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    all) WANT_ALL=1; WANT_SERVICE=1; WANT_ADMIN=1; WANT_WEB=1; WANT_APP=1 ;;
    service|api) WANT_SERVICE=1 ;;
    admin) WANT_ADMIN=1 ;;
    web) WANT_WEB=1 ;;
    app) WANT_APP=1 ;;
    *)
      if is_flutter_device "$t"; then
        FLUTTER_DEVICE="$t"
        WANT_APP=1
      else
        err "[错误] 未知目标: $token"
        warn "运行 ./run.sh help 查看用法"
        exit 1
      fi
      ;;
  esac
done

if [[ "$WANT_APP" -eq 1 && -z "$FLUTTER_DEVICE" ]]; then
  case "$(uname -s)" in
    Darwin) FLUTTER_DEVICE="macos" ;;
    Linux)  FLUTTER_DEVICE="linux" ;;
    MINGW*|MSYS*|CYGWIN*) FLUTTER_DEVICE="windows" ;;
  esac
fi

if [[ "$WANT_SERVICE$WANT_ADMIN$WANT_WEB$WANT_APP" == "0000" ]]; then
  show_help
  exit 0
fi

NEED_SERVICE=$((WANT_SERVICE + WANT_ADMIN + WANT_WEB))
DEV_MODE=0
[[ "$WANT_SERVICE" -eq 0 && "$WANT_WEB" -eq 1 ]] && DEV_MODE=1

print_install_hint() {
  case "$1" in
    go)
      err "  缺少 Go"; warn "  https://go.dev/dl/ | brew install go | sudo apt install golang-go" ;;
    wf)
      err "  缺少 webfront wf CLI"
      warn "  go install github.com/plunjoin/webfront/cmd/wf@v0.1.0" ;;
    flutter)
      err "  缺少 Flutter"; warn "  https://docs.flutter.dev/get-started/install" ;;
  esac
}

echo ""
ok "=== video-collection 环境检查 ==="

MISSING=0
WF_CMD=""
if [[ "$NEED_SERVICE" -gt 0 ]]; then
  if have_cmd go; then ok "[OK] go $(go version 2>/dev/null | awk '{print $3}')"
  else print_install_hint go; MISSING=1; fi

  # 仓库根的 wf.exe 是 Windows 二进制，macOS / Linux 用 PATH 里的 wf
  if have_cmd wf; then
    WF_CMD="wf"
    ok "[OK] wf CLI: $(command -v wf)"
  else
    print_install_hint wf; MISSING=1
  fi
fi

if [[ "$WANT_APP" -eq 1 ]]; then
  if have_cmd flutter; then ok "[OK] flutter $(flutter --version 2>/dev/null | head -n1)"
  else print_install_hint flutter; MISSING=1; fi
fi

if [[ "$MISSING" -eq 1 ]]; then
  echo ""; err "[中止] 请先安装缺失的运行环境后再重试。"; exit 1
fi

SERVICE_DIR="$ROOT/video-collection-service"

ensure_go_deps() {
  [[ -d "$SERVICE_DIR" ]] || { warn "[跳过] Service 目录不存在"; return 0; }
  info "[依赖] Service: go mod download"
  (cd "$SERVICE_DIR" && go mod download)
}

ensure_wf_deps() {
  if [[ -f "$SERVICE_DIR/web/wf_modules/.store/manifest.json" ]]; then
    dim "[依赖] 前端: wf_modules 已存在，跳过"
    return 0
  fi
  info "[依赖] 前端: wf install（零 Node，按 web/package-lock.json 锁定版本）..."
  (cd "$SERVICE_DIR" && "$WF_CMD" install -modules wf_modules .)
}

build_admin_frontend() {
  info "[构建] 管理后台: wf build（esbuild，秒级）..."
  (cd "$SERVICE_DIR" && "$WF_CMD" build -mode spa -base /admin -modules ../wf_modules web/admin)
}

build_portal_frontend() {
  info "[构建] 门户: wf build（SSR bundle + 分包）..."
  (cd "$SERVICE_DIR" && "$WF_CMD" build -modules ../wf_modules web/portal)
}

ensure_flutter_deps() {
  local dir="$ROOT/video-collection-app"
  [[ -d "$dir" ]] || { warn "[跳过] App 目录不存在"; return 0; }
  info "[依赖] App: flutter pub get"
  (cd "$dir" && flutter pub get)
}

echo ""
ok "=== 检查 / 安装项目依赖 ==="
[[ "$NEED_SERVICE" -gt 0 ]] && ensure_go_deps
[[ "$NEED_SERVICE" -gt 0 ]] && ensure_wf_deps
[[ "$WANT_ADMIN" -eq 1 ]] && build_admin_frontend
[[ "$WANT_ALL" -eq 1 ]] && build_portal_frontend
[[ "$WANT_APP" -eq 1 ]] && ensure_flutter_deps

# ---------- 同一终端并行启动 ----------
PIDS=()

cleanup() {
  trap - INT TERM EXIT
  echo ""
  warn "正在停止全部服务..."
  local pid
  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      # 结束进程组（子进程一并退出）
      kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    fi
  done
  sleep 0.4
  for pid in "${PIDS[@]:-}"; do
    kill -KILL -"$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  ok "已全部停止。"
}

trap cleanup INT TERM EXIT

start_one() {
  local tag="$1" dir="$2" cmd="$3"

  if [[ ! -d "$dir" ]]; then
    warn "[跳过] $tag — 目录不存在: $dir"
    return 0
  fi

  info "[启动] $tag"
  dim "       $cmd"

  # 独立进程组，便于 Ctrl+C 时整组杀掉；stdout/stderr 合并后加前缀
  (
    cd "$dir" || exit 1
    # shellcheck disable=SC2086
    bash -c "$cmd" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
      printf '[%s] %s\n' "$tag" "$line"
    done
  ) &
  PIDS+=($!)
}

echo ""
ok "=== 启动服务（同一终端） ==="
echo "app     : $( [[ "$WANT_APP" -eq 1 ]] && echo "app/${FLUTTER_DEVICE:-default}" || echo "(none)" )"
echo ""
warn "日志前缀区分服务。按 Ctrl+C 停止全部。"
echo ""

if [[ "$NEED_SERVICE" -gt 0 ]]; then
  cmd="go run ."
  tag="service"
  if [[ "$DEV_MODE" -eq 1 ]]; then
    cmd="go run -tags dev ."
    tag="web"
    info "[web] 门户与管理后台均挂 webfront DevServer（HMR）"
  elif [[ "$WANT_WEB" -eq 1 ]]; then
    dim "[web] 与 service 同进程，门户走内嵌产物；需要 HMR 请单选 web"
  fi
  start_one "$tag" "$SERVICE_DIR" "$cmd"
fi

if [[ "$WANT_APP" -eq 1 ]]; then
  cmd="flutter run"
  [[ -n "$FLUTTER_DEVICE" ]] && cmd="flutter run -d $FLUTTER_DEVICE"
  start_one "app" "$ROOT/video-collection-app" "$cmd"
fi

if [[ ${#PIDS[@]} -eq 0 ]]; then
  trap - INT TERM EXIT
  err "[中止] 没有可启动的服务"
  exit 1
fi

# 任一子进程退出后继续等到全部结束（或 Ctrl+C）
wait || true
trap - INT TERM EXIT
ok "全部服务已结束。"
