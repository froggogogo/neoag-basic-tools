#!/usr/bin/env bash
# Shared helpers for neoag-basic-tools-install
# shellcheck disable=SC2034

set -euo pipefail

NEOAG_INSTALL_VERSION="1.2.0"

log()  { printf '[%s] INFO  %s\n'  "$(date '+%F %T')" "$*"; }
ok()   { printf '[%s] OK    %s\n'  "$(date '+%F %T')" "$*"; }
warn() { printf '[%s] WARN  %s\n'  "$(date '+%F %T')" "$*" >&2; }
err()  { printf '[%s] ERROR %s\n'  "$(date '+%F %T')" "$*" >&2; }

die() {
  local code="${1:-GENERIC}"
  shift || true
  err "reason=${code}"
  err "$*"
  err "hint=查看 README.md 参数说明；或加 --mode plan 先预览"
  exit 1
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "MISSING_CMD" "缺少命令: $c。请先安装系统依赖（见 README）。"
  done
}

is_forbidden_conda_dir() {
  local d
  d="$(cd "$1" 2>/dev/null && pwd -P || echo "$1")"
  case "$d" in
    /|/usr|/usr/*|/bin|/sbin|/etc|/var|/boot)
      return 0
      ;;
  esac
  # Default: forbid /root and anything under it (override with --allow-root-conda)
  if [[ "${ALLOW_ROOT_CONDA:-0}" != "1" ]]; then
    if [[ "$d" == /root || "$d" == /root/* ]]; then
      return 0
    fi
  fi
  return 1
}

abspath() {
  local p="$1"
  if [[ -d "$p" ]]; then
    (cd "$p" && pwd -P)
  else
    local dir base
    dir="$(cd "$(dirname "$p")" && pwd -P)"
    base="$(basename "$p")"
    echo "${dir}/${base}"
  fi
}

ensure_dir() {
  local d="$1"
  local mode="${2:-}"
  mkdir -p "$d" || die "MKDIR_FAILED" "无法创建目录: $d"
  if [[ -n "$mode" ]]; then
    chmod "$mode" "$d" || warn "无法 chmod $mode $d（可能无权限，继续）"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  local dir
  dir="$(dirname "$path")"
  ensure_dir "$dir"
  printf '%s\n' "$content" >"$path"
}

# Check mount presence for a path prefix
require_mount_prefix() {
  local prefix="$1"
  local name="$2"
  if [[ ! -d "$prefix" ]]; then
    die "MOUNT_MISSING" \
      "${name} 路径不存在: ${prefix}。请确认已挂载 NAS，或用 --deps-dir / --asset-source 指定可达路径。"
  fi
}

# Returns 0 if host is Ubuntu 22.04 (EasyFuse hard requirement).
is_ubuntu_2204() {
  local id ver
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    ver="${VERSION_ID:-}"
    [[ "$id" == "ubuntu" && "$ver" == "22.04" ]] && return 0
  fi
  return 1
}

detect_os_summary() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${NAME:-unknown} ${VERSION_ID:-?} ($(uname -m))"
  else
    echo "$(uname -s) $(uname -r) $(uname -m)"
  fi
}

# Export EasyFuse capability for site.env / verify / installers
refresh_easyfuse_capability() {
  local os
  os="$(detect_os_summary)"
  if is_ubuntu_2204; then
    export NEOAG_EASYFUSE_SUPPORTED=1
    export NEOAG_EASYFUSE_SKIP_REASON=""
    ok "EasyFuse 系统检查通过: ${os}（需要 Ubuntu 22.04）"
  else
    export NEOAG_EASYFUSE_SUPPORTED=0
    export NEOAG_EASYFUSE_SKIP_REASON="EasyFuse 仅支持 Ubuntu 22.04；当前为 ${os}，本机跳过 EasyFuse 运行态安装"
    warn "${NEOAG_EASYFUSE_SKIP_REASON}"
    warn "refs 仍可同步到 deps；请在 Ubuntu 22.04 机器上跑 EasyFuse，或改用 STAR-Fusion 等替代 fusion caller"
  fi
}
