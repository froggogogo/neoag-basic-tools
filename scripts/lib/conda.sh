#!/usr/bin/env bash
# Conda discovery + optional Miniforge install
# shellcheck source=/dev/null

discover_conda() {
  local cand exe=""
  local -a cands=()

  if [[ -n "${CONDA_EXE:-}" && -x "${CONDA_EXE}" ]]; then
    cands+=("${CONDA_EXE}")
  fi
  if command -v conda >/dev/null 2>&1; then
    cands+=("$(command -v conda)")
  fi
  if command -v mamba >/dev/null 2>&1; then
    # prefer real conda base from mamba later
    :
  fi

  # Explicit user / deps locations first
  cands+=(
    "${CONDA_DIR:-}/bin/conda"
    "${DEPS_DIR}/software/miniforge3/bin/conda"
    "${HOME}/.local/neoag-miniforge3/bin/conda"
    "${HOME}/miniforge3/bin/conda"
    "${HOME}/mambaforge/bin/conda"
    "${HOME}/miniconda3/bin/conda"
    "/opt/miniforge3/bin/conda"
    "/opt/miniconda3/bin/conda"
    "/mnt/zzbnew/peixunban/gl/miniconda3/bin/conda"
    "/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/software/miniforge3/bin/conda"
    "/mnt/zzbnew/peixunban/gl/neoag_basic_deps/software/miniforge3/bin/conda"
    "/home/na/miniforge3/bin/conda"
    "/root/neo/envs/miniforge3/bin/conda"
    "/root/miniforge3/bin/conda"
    "/root/miniconda3/bin/conda"
  )

  for cand in "${cands[@]}"; do
    [[ -z "$cand" || "$cand" == "/bin/conda" ]] && continue
    if [[ -x "$cand" ]]; then
      exe="$cand"
      break
    fi
  done

  if [[ -z "$exe" ]]; then
    return 1
  fi

  CONDA_EXE="$exe"
  CONDA_BASE="$(cd "$(dirname "$exe")/.." && pwd -P)"
  export CONDA_EXE CONDA_BASE
  ok "发现 Conda: CONDA_EXE=${CONDA_EXE} CONDA_BASE=${CONDA_BASE}"
  resolve_mamba_exe
  return 0
}

install_miniforge() {
  local target="${1:?conda target dir}"
  local arch os url installer
  require_cmd curl uname bash

  if is_forbidden_conda_dir "$target"; then
    die "FORBIDDEN_CONDA_DIR" \
      "拒绝安装到系统敏感路径: ${target}。请使用 --conda-dir（例如 \$HOME/.local/neoag-miniforge3 或 \$DEPS_DIR/software/miniforge3）。若确需 /root 下，加 --allow-root-conda。"
  fi

  ensure_dir "$(dirname "$target")"
  if [[ -x "${target}/bin/conda" ]]; then
    ok "Conda 已存在: ${target}"
    CONDA_EXE="${target}/bin/conda"
    CONDA_BASE="$(cd "$target" && pwd -P)"
    export CONDA_EXE CONDA_BASE
    resolve_mamba_exe
    return 0
  fi

  os="$(uname -s)"
  arch="$(uname -m)"
  case "${os}-${arch}" in
    Linux-x86_64)  installer="Miniforge3-Linux-x86_64.sh" ;;
    Linux-aarch64) installer="Miniforge3-Linux-aarch64.sh" ;;
    Darwin-arm64)  installer="Miniforge3-MacOSX-arm64.sh" ;;
    Darwin-x86_64) installer="Miniforge3-MacOSX-x86_64.sh" ;;
    *) die "UNSUPPORTED_ARCH" "不支持的平台: ${os}-${arch}" ;;
  esac

  url="https://github.com/conda-forge/miniforge/releases/latest/download/${installer}"
  # Prefer cached installer in deps packages if present (intranet)
  local cache="${DEPS_DIR}/packages/installers/${installer}"
  ensure_dir "$(dirname "$cache")"
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if [[ -f "$cache" ]]; then
    log "使用缓存安装包: $cache"
    cp -f "$cache" "${tmp}/${installer}"
  else
    log "下载 Miniforge: $url"
    if ! curl -fsSL --connect-timeout 20 --retry 3 -o "${tmp}/${installer}" "$url"; then
      die "DOWNLOAD_FAILED" \
        "无法下载 Miniforge。请将 ${installer} 放到 ${cache} 后重试，或检查外网/代理。"
    fi
    cp -f "${tmp}/${installer}" "$cache" || true
    chmod a+rw "$cache" 2>/dev/null || true
  fi

  log "安装 Miniforge -> ${target}"
  bash "${tmp}/${installer}" -b -p "$target" || die "CONDA_INSTALL_FAILED" "Miniforge 安装失败: $target"

  CONDA_EXE="${target}/bin/conda"
  CONDA_BASE="$(cd "$target" && pwd -P)"
  export CONDA_EXE CONDA_BASE
  # pkgs cache on shared deps
  ensure_dir "${DEPS_DIR}/packages/conda_pkgs" 1777
  "${CONDA_EXE}" config --set pkgs_dirs "${DEPS_DIR}/packages/conda_pkgs" || true
  "${CONDA_EXE}" config --add envs_dirs "${CONDA_BASE}/envs" || true
  ok "Miniforge 安装完成: ${CONDA_BASE}"
  resolve_mamba_exe
}

# Prefer mamba for env create / package install (same yml, faster solve). Fallback: conda.
resolve_mamba_exe() {
  MAMBA_EXE=""
  local cand
  local -a cands=()
  [[ -n "${CONDA_BASE:-}" ]] && cands+=("${CONDA_BASE}/bin/mamba" "${CONDA_BASE}/condabin/mamba")
  if command -v mamba >/dev/null 2>&1; then
    cands+=("$(command -v mamba)")
  fi
  cands+=(
    "${DEPS_DIR}/software/miniforge3/bin/mamba"
    "/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/software/miniforge3/bin/mamba"
    "${HOME}/miniforge3/bin/mamba"
    "${HOME}/mambaforge/bin/mamba"
  )
  for cand in "${cands[@]}"; do
    [[ -n "$cand" && -x "$cand" ]] || continue
    MAMBA_EXE="$cand"
    break
  done
  if [[ -n "$MAMBA_EXE" ]]; then
    CONDA_FRONTEND="$MAMBA_EXE"
    export MAMBA_EXE CONDA_FRONTEND
    ok "环境安装前端: mamba (${MAMBA_EXE})"
  else
    CONDA_FRONTEND="${CONDA_EXE:?}"
    export CONDA_FRONTEND
    warn "未找到 mamba，回退 conda 创建/安装环境（较慢）: ${CONDA_FRONTEND}"
  fi
}

# Run: env create / install via mamba when available.
conda_frontend() {
  if [[ -z "${CONDA_FRONTEND:-}" ]]; then
    resolve_mamba_exe
  fi
  "${CONDA_FRONTEND}" "$@"
}

resolve_conda() {
  # Prefer deps-dir conda when ONE_SHOT / PREFER_DEPS_CONDA (portable across hosts).
  if [[ "${PREFER_DEPS_CONDA:-0}" == "1" ]]; then
    local deps_conda="${DEPS_DIR}/software/miniforge3/bin/conda"
    if [[ -x "$deps_conda" ]]; then
      CONDA_EXE="$deps_conda"
      CONDA_BASE="$(cd "$(dirname "$deps_conda")/.." && pwd -P)"
      export CONDA_EXE CONDA_BASE
      ok "使用 deps 内 Conda: ${CONDA_BASE}"
      resolve_mamba_exe
      return 0
    fi
    if [[ "${MODE}" == "plan" || "${MODE}" == "verify" ]]; then
      warn "prefer-deps-conda：deps 内尚无 Miniforge（plan/verify 不自动安装）"
      # fall through to discover for verify visibility
    else
      local target="${CONDA_DIR:-${DEPS_DIR}/software/miniforge3}"
      log "prefer-deps-conda：安装 Miniforge -> ${target}"
      install_miniforge "$target"
      return 0
    fi
  fi

  # Priority: reuse -> install into CONDA_DIR
  if discover_conda; then
    return 0
  fi
  if [[ "${MODE}" == "plan" || "${MODE}" == "verify" ]]; then
    warn "未发现可用 Conda（plan/verify 不自动安装）"
    return 1
  fi
  local target="${CONDA_DIR}"
  if [[ -z "$target" ]]; then
    if [[ "${PREFER_DEPS_CONDA:-0}" == "1" ]]; then
      target="${DEPS_DIR}/software/miniforge3"
    else
      target="${HOME}/.local/neoag-miniforge3"
    fi
  fi
  log "未发现 Conda，将安装到: ${target}"
  install_miniforge "$target"
}
