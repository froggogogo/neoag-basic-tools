#!/usr/bin/env bash
# neoag-basic-tools-install — portable A1 single-host installer
# Intranet-ready: centralized deps on neoag_100T, parameterized paths, no machine hardcoding.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/conda.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/deps_dir.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/sync_assets.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/install_envs.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/runtime_hardening.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/verify.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/install.sh --mode <plan|install|verify|sync|envs> [options]

Modes:
  plan     预览动作，不改系统
  install  一键：初始化 deps + conda + 同步资产 + site.env [+envs/tools]
  sync     仅同步资产到 deps-dir（可将软链物化为 copy）
  envs     仅创建基础 conda 环境 / 跑工具安装脚本
  verify   验收：refs 存在且可读、conda env、关键 R 包冒烟

Options:
  --deps-dir DIR          统一依赖目录（默认 /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps）
  --conda-dir DIR         Conda 安装目录（未发现时使用；--one-shot 默认装到 deps/software/miniforge3）
  --asset-source DIR      资产源（默认 /mnt/zjl-bgi-zzb/peixunban/gl/liup/neodata4git）
  --neo-src DIR           neo 流水线源码
  --sync-mode MODE        copy|symlink|auto（默认 copy：资产落入 neoag_100T，不依赖 zjl 可读）
  --one-shot              推荐：copy + envs + tool-scripts + conda 优先装进 deps-dir
  --with-envs             install 时创建基础 conda 环境
  --with-tool-scripts     install/envs 时执行 neo scripts/install_*.sh
  --prefer-deps-conda     优先使用/安装 $DEPS_DIR/software/miniforge3
  --force-resync          sync/copy 时拆除已有软链并覆盖同步
  --continue-on-error     单步失败不中断
  --allow-root-conda      允许 conda 装在 /root 下（不推荐）
  --yes                   跳过确认（mutating 模式需要）
  -h, --help              帮助

Examples:
  # 挂载了 neoag_100T + zjl 的机器上：一键装完并验收
  bash scripts/install.sh --mode install --one-shot --yes

  # 把现有软链 refs 物化进 neoag_100T（解决「源盘不让读」）
  bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync

  bash scripts/install.sh --mode plan
  bash scripts/install.sh --mode verify
EOF
}

MODE="install"
DEPS_DIR="${DEFAULT_DEPS_DIR}"
CONDA_DIR=""
ASSET_SOURCE="/mnt/zjl-bgi-zzb/peixunban/gl/liup/neodata4git"
NEO_SRC=""
SYNC_MODE="copy"
WITH_ENVS=0
WITH_TOOL_SCRIPTS=0
CONTINUE_ON_ERROR=0
ALLOW_ROOT_CONDA=0
PREFER_DEPS_CONDA=0
FORCE_RESYNC=0
ONE_SHOT=0
YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:?}"; shift 2 ;;
    --deps-dir) DEPS_DIR="${2:?}"; shift 2 ;;
    --conda-dir) CONDA_DIR="${2:?}"; shift 2 ;;
    --asset-source) ASSET_SOURCE="${2:?}"; shift 2 ;;
    --neo-src) NEO_SRC="${2:?}"; shift 2 ;;
    --sync-mode) SYNC_MODE="${2:?}"; shift 2 ;;
    --one-shot) ONE_SHOT=1; shift ;;
    --with-envs) WITH_ENVS=1; shift ;;
    --with-tool-scripts) WITH_TOOL_SCRIPTS=1; shift ;;
    --prefer-deps-conda) PREFER_DEPS_CONDA=1; shift ;;
    --force-resync) FORCE_RESYNC=1; shift ;;
    --continue-on-error) CONTINUE_ON_ERROR=1; shift ;;
    --allow-root-conda) ALLOW_ROOT_CONDA=1; shift ;;
    --yes|-y) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "BAD_ARG" "未知参数: $1" ;;
  esac
done

if [[ "$ONE_SHOT" == "1" ]]; then
  WITH_ENVS=1
  WITH_TOOL_SCRIPTS=1
  PREFER_DEPS_CONDA=1
  # keep user override of sync-mode if they passed it before/after; default remains copy
  if [[ -z "${CONDA_DIR}" ]]; then
    CONDA_DIR="${DEPS_DIR}/software/miniforge3"
  fi
  log "one-shot：sync-mode=${SYNC_MODE} with-envs=1 tools=1 prefer-deps-conda=1 conda-dir=${CONDA_DIR}"
fi

export MODE DEPS_DIR CONDA_DIR ASSET_SOURCE NEO_SRC SYNC_MODE
export WITH_ENVS WITH_TOOL_SCRIPTS CONTINUE_ON_ERROR ALLOW_ROOT_CONDA YES
export PREFER_DEPS_CONDA FORCE_RESYNC ONE_SHOT

# Resolve neo install slice: prefer deps (skill independent of neo git).
if [[ -z "${NEO_SRC}" ]]; then
  for cand in \
    "${DEPS_DIR}/src/neo" \
    "${PWD}/neo" \
    "${HOME}/neo"
  do
    if [[ -f "${cand}/pyproject.toml" || -f "${cand}/README.md" || -f "${cand}/conda/env.neoag-tools.yml" ]]; then
      NEO_SRC="$cand"
      break
    fi
  done
fi
export NEO_SRC

confirm_mutate() {
  if [[ "$YES" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "NEED_YES" "非交互环境请加 --yes 以确认写入操作"
  fi
  read -r -p "将写入 ${DEPS_DIR} 并可能安装软件，确认继续？[y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "ABORTED" "用户取消"
}

print_plan() {
  refresh_easyfuse_capability || true
  cat <<EOF
======== neoag-basic-tools-install plan ========
version:     ${NEOAG_INSTALL_VERSION}
mode:        ${MODE}
deps-dir:    ${DEPS_DIR}
conda-dir:   ${CONDA_DIR:-"(auto)"}
asset-source:${ASSET_SOURCE}
neo-src:     ${NEO_SRC:-"(not found)"}
sync-mode:   ${SYNC_MODE}
one-shot:    ${ONE_SHOT}
with-envs:   ${WITH_ENVS}
with-tools:  ${WITH_TOOL_SCRIPTS}
prefer-deps-conda: ${PREFER_DEPS_CONDA}
force-resync:${FORCE_RESYNC}
os:          $(detect_os_summary)
easyfuse:    supported=${NEOAG_EASYFUSE_SUPPORTED:-?} (Ubuntu 22.04 only)
===============================================
EOF
}

run_install() {
  confirm_mutate
  require_cmd mkdir chmod find date
  init_deps_layout
  write_deps_readme
  local logf="${DEPS_DIR}/logs/install_$(date +%Y%m%d_%H%M%S).log"
  log "日志: $logf"
  {
    log "==== install start ===="
    if ! resolve_conda; then
      die "NO_CONDA" "无法获得 Conda"
    fi

    sync_assets
    render_site_env

    if [[ "$WITH_ENVS" == "1" ]]; then
      install_basic_envs
    else
      log "跳过 conda env 创建（需要时加 --with-envs 或 --one-shot）"
    fi
    if [[ "$WITH_TOOL_SCRIPTS" == "1" ]]; then
      run_tool_installers
    else
      log "跳过 neo install_*.sh（需要时加 --with-tool-scripts 或 --one-shot）"
    fi

    log "应用运行期加固（Sequenza chrom-split / samtools 1.9 / MHCflurry / fit 补丁）"
    apply_runtime_hardening || true

    set +e
    verify_installation
    local vr=$?
    set -e
    if [[ "$vr" -ne 0 ]]; then
      warn "验收未完全通过；请根据 manifests/verify_report.tsv 修复后重跑 --mode verify"
      return 1
    fi
    ok "安装流程完成"
  } 2>&1 | tee -a "$logf"
  return "${PIPESTATUS[0]}"
}

main() {
  case "$MODE" in
    plan)
      print_plan
      if [[ -d "/mnt/neoag_100T" ]]; then ok "neoag_100T 挂载可见"; else warn "未见 /mnt/neoag_100T"; fi
      if [[ -d "/mnt/zjl-bgi-zzb" ]]; then ok "zjl-bgi-zzb 挂载可见"; else warn "未见 /mnt/zjl-bgi-zzb（copy/symlink 灌库需要）"; fi
      if discover_conda || [[ "${PREFER_DEPS_CONDA}" == "1" ]]; then
        :
      else
        warn "当前未发现 Conda；install 时将安装到 ${CONDA_DIR:-$HOME/.local/neoag-miniforge3}"
      fi
      if [[ -d "$DEPS_DIR" ]]; then
        ok "deps-dir 已存在"
      else
        log "deps-dir 尚不存在，install 时将创建"
      fi
      if [[ -d "$ASSET_SOURCE" ]]; then
        if asset_readable "$ASSET_SOURCE"; then
          ok "asset-source 可达且可读（仅缺项灌库时需要）"
        else
          warn "asset-source 存在但不可读: $ASSET_SOURCE（deps 已齐则可忽略）"
        fi
      else
        warn "asset-source 不可达: $ASSET_SOURCE（deps 已齐则可忽略，不必挂 zjl）"
      fi
      [[ -n "$NEO_SRC" && -d "$NEO_SRC" ]] && ok "neo-src 可达: $NEO_SRC" || warn "neo-src 未找到"
      ok "plan 完成（无写入）"
      ;;
    install)
      print_plan
      run_install
      ;;
    sync)
      confirm_mutate
      init_deps_layout
      sync_assets
      render_site_env
      ;;
    envs)
      confirm_mutate
      [[ -d "$DEPS_DIR" ]] || die "DEPS_MISSING" "请先 --mode install 初始化 deps"
      resolve_conda || die "NO_CONDA" "需要 conda"
      # shellcheck disable=SC1090
      [[ -f "${DEPS_DIR}/configs/site.env.sh" ]] && source "${DEPS_DIR}/configs/site.env.sh"
      install_basic_envs
      if [[ "$WITH_TOOL_SCRIPTS" == "1" ]]; then
        run_tool_installers
      fi
      apply_runtime_hardening || true
      render_site_env
      ;;
    verify)
      print_plan
      verify_installation
      ;;
    *)
      usage
      die "BAD_MODE" "未知 mode: $MODE"
      ;;
  esac
}

main
