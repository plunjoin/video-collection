#!/usr/bin/env bash
# 一键启动 video-collection（同一终端并行，Ctrl+C 全部停止）
# 用法: ./run.sh admin web macos

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

所有服务在当前终端并行运行，日志带 [api]/[admin]/[web]/[app] 前缀。
按 Ctrl+C 停止全部。

用法:
  ./run.sh <目标...>
  ./run.sh help

项目目标:
  api / admin / web / app / all
  Flutter 平台: windows android ios macos linux chrome edge web-server

示例:
  ./run.sh admin web macos
  ./run.sh api admin web android
  ./run.sh all
  ./run.sh web

说明:
  - 缺少运行时会提示安装方式并退出
  - 缺少项目依赖会自动安装
  - 自动使用 UTF-8 locale，避免中文乱码
  - Windows 请使用 run.ps1 或 run.cmd
EOF
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "help" ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

WANT_API=0
WANT_ADMIN=0
WANT_WEB=0
WANT_APP=0
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
    all) WANT_API=1; WANT_ADMIN=1; WANT_WEB=1; WANT_APP=1 ;;
    api) WANT_API=1 ;;
    admin) WANT_ADMIN=1 ;;
    web|astro) WANT_WEB=1 ;;
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

if [[ "$WANT_API$WANT_ADMIN$WANT_WEB$WANT_APP" == "0000" ]]; then
  show_help
  exit 0
fi

MISSING=0
NEED_NODE=0
[[ "$WANT_ADMIN" -eq 1 || "$WANT_WEB" -eq 1 ]] && NEED_NODE=1

print_install_hint() {
  case "$1" in
    go)
      err "  缺少 Go"; warn "  https://go.dev/dl/ | brew install go | sudo apt install golang-go" ;;
    node)
      err "  缺少 Node.js"; warn "  https://nodejs.org/ | brew install node" ;;
    pnpm)
      err "  缺少 pnpm"; warn "  corepack enable && corepack prepare pnpm@latest --activate" ;;
    flutter)
      err "  缺少 Flutter"; warn "  https://docs.flutter.dev/get-started/install" ;;
  esac
}

ensure_pnpm() {
  have_cmd pnpm && return 0
  have_cmd node || return 1
  info "[环境] 未找到 pnpm，尝试 corepack / npm ..."
  if have_cmd corepack; then
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
    have_cmd pnpm && { ok "[环境] pnpm $(pnpm -v)"; return 0; }
  fi
  if have_cmd npm; then
    npm install -g pnpm >/dev/null 2>&1 || true
    have_cmd pnpm && { ok "[环境] pnpm $(pnpm -v)"; return 0; }
  fi
  return 1
}

echo ""
ok "=== video-collection 环境检查 ==="

if [[ "$WANT_API" -eq 1 ]]; then
  if have_cmd go; then ok "[OK] go $(go version 2>/dev/null | awk '{print $3}')"
  else print_install_hint go; MISSING=1; fi
fi

if [[ "$NEED_NODE" -eq 1 ]]; then
  if have_cmd node; then ok "[OK] node $(node -v)"
  else print_install_hint node; MISSING=1; fi
  if [[ "$MISSING" -eq 0 ]]; then
    if ensure_pnpm; then ok "[OK] pnpm $(pnpm -v)"
    else print_install_hint pnpm; MISSING=1; fi
  fi
fi

if [[ "$WANT_APP" -eq 1 ]]; then
  if have_cmd flutter; then ok "[OK] flutter $(flutter --version 2>/dev/null | head -n1)"
  else print_install_hint flutter; MISSING=1; fi
fi

if [[ "$MISSING" -eq 1 ]]; then
  echo ""; err "[中止] 请先安装缺失的运行环境后再重试。"; exit 1
fi

ensure_go_deps() {
  local dir="$ROOT/video-collection-api"
  [[ -d "$dir" ]] || { warn "[跳过] API 目录不存在"; return 0; }
  info "[依赖] API: go mod download"
  (cd "$dir" && go mod download)
}

ensure_pnpm_deps() {
  local name="$1" dir="$2"
  [[ -d "$dir" ]] || { warn "[跳过] $name 目录不存在"; return 0; }
  if [[ ! -d "$dir/node_modules" ]]; then
    info "[依赖] $name: pnpm install ..."
    (cd "$dir" && pnpm install)
  else
    dim "[依赖] $name: node_modules 已存在，跳过"
  fi
}

ensure_flutter_deps() {
  local dir="$ROOT/video-collection-app"
  [[ -d "$dir" ]] || { warn "[跳过] App 目录不存在"; return 0; }
  info "[依赖] App: flutter pub get"
  (cd "$dir" && flutter pub get)
}

echo ""
ok "=== 检查 / 安装项目依赖 ==="
[[ "$WANT_API" -eq 1 ]] && ensure_go_deps
[[ "$WANT_ADMIN" -eq 1 ]] && ensure_pnpm_deps "Admin" "$ROOT/video-collection-admin"
[[ "$WANT_WEB" -eq 1 ]] && ensure_pnpm_deps "Web" "$ROOT/video-collection-web"
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
projects=""
[[ "$WANT_API" -eq 1 ]] && projects+="api "
[[ "$WANT_ADMIN" -eq 1 ]] && projects+="admin "
[[ "$WANT_WEB" -eq 1 ]] && projects+="web "
echo "projects: ${projects:-"(none)"}"
if [[ "$WANT_APP" -eq 1 ]]; then echo "app     : app/${FLUTTER_DEVICE:-default}"
else echo "app     : (none)"; fi
echo ""
warn "日志前缀区分服务。按 Ctrl+C 停止全部。"
echo ""

[[ "$WANT_API" -eq 1 ]] && start_one "api" "$ROOT/video-collection-api" "go run ."
[[ "$WANT_ADMIN" -eq 1 ]] && start_one "admin" "$ROOT/video-collection-admin" "pnpm dev"
[[ "$WANT_WEB" -eq 1 ]] && start_one "web" "$ROOT/video-collection-web" "pnpm start"

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
