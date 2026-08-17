#!/usr/bin/env bash
# Runtime hardening helpers (Sequenza data.table, MHCflurry layout).
# Sourced from install.sh / install_envs.sh.

ensure_sequenza_datatable() {
  local env_prefix="${CONDA_BASE}/envs/neoag-sequenza"
  local rscript="${env_prefix}/bin/Rscript"
  [[ -d "$env_prefix" ]] || return 0
  [[ -x "$rscript" ]] || {
    warn "neoag-sequenza 无 Rscript，跳过 r-data.table"
    return 0
  }

  if "$rscript" -e 'cat(requireNamespace("data.table", quietly=TRUE), "\n")' 2>/dev/null | grep -q TRUE; then
    ok "neoag-sequenza 已具备 data.table"
    return 0
  fi

  log "安装 r-data.table 到 neoag-sequenza（Sequenza fit fread 必需）"
  ensure_dir "${DEPS_DIR}/logs" 777
  local ok_install=0
  if declare -F conda_frontend >/dev/null 2>&1; then
    if conda_frontend install -y -n neoag-sequenza -c conda-forge r-data.table \
        >"${DEPS_DIR}/logs/r_datatable_conda.out" 2>"${DEPS_DIR}/logs/r_datatable_conda.err"; then
      ok_install=1
    fi
  elif [[ -n "${CONDA_EXE:-}" ]] && "${CONDA_EXE}" install -y -n neoag-sequenza -c conda-forge r-data.table \
      >"${DEPS_DIR}/logs/r_datatable_conda.out" 2>"${DEPS_DIR}/logs/r_datatable_conda.err"; then
    ok_install=1
  fi
  if [[ "$ok_install" -eq 1 ]]; then
    ok "mamba/conda 安装 r-data.table 成功"
  else
    warn "mamba/conda 安装 r-data.table 失败，见 ${DEPS_DIR}/logs/r_datatable_conda.err"
    return 1
  fi

  if "$rscript" -e 'cat(requireNamespace("data.table", quietly=TRUE), "\n")' 2>/dev/null | grep -q TRUE; then
    ok "data.table 冒烟通过"
    return 0
  fi
  warn "安装后仍无法加载 data.table"
  return 1
}

# Align MHCflurry download layout: expect …/mhcflurry/2.0.0/… but downloads may
# land under …/mhcflurry/4/2.0.0/…. Also prefer a deps-local data dir when present.
ensure_mhcflurry_layout() {
  ensure_dir "${DEPS_DIR}/packages" 777
  local -a candidates=()
  local u home_mf
  home_mf="${HOME:-}/.local/share/mhcflurry"
  [[ -n "${HOME:-}" && -d "$home_mf" ]] && candidates+=("$home_mf")

  # Common service accounts on intranet hosts
  for u in na root; do
    if [[ -d "/home/${u}/.local/share/mhcflurry" ]]; then
      candidates+=("/home/${u}/.local/share/mhcflurry")
    fi
  done
  if [[ -d /root/.local/share/mhcflurry ]]; then
    candidates+=("/root/.local/share/mhcflurry")
  fi

  local deps_mf="${DEPS_DIR}/packages/mhcflurry_data"
  if [[ -d "$deps_mf" ]]; then
    candidates+=("$deps_mf")
  fi

  local mf fixed=0
  local -A seen=()
  for mf in "${candidates[@]}"; do
    [[ -n "${seen[$mf]:-}" ]] && continue
    seen[$mf]=1
    [[ -d "$mf" ]] || continue
    if [[ -d "${mf}/4/2.0.0/models_class1_presentation" && ! -e "${mf}/2.0.0" ]]; then
      ln -sfn "${mf}/4/2.0.0" "${mf}/2.0.0"
      ok "MHCflurry layout shim: ${mf}/2.0.0 -> 4/2.0.0"
      fixed=1
    elif [[ -e "${mf}/2.0.0/models_class1_presentation" || -L "${mf}/2.0.0" ]]; then
      ok "MHCflurry 2.0.0 path OK: ${mf}/2.0.0"
      fixed=1
    fi
  done

  # Prefer writing MHCFLURRY_DATA_DIR hint file for site.env consumers
  local hint="${DEPS_DIR}/configs/mhcflurry_data_dir.txt"
  if [[ -d "${deps_mf}/2.0.0/models_class1_presentation" || -L "${deps_mf}/2.0.0" ]]; then
    printf '%s\n' "$deps_mf" >"$hint"
  elif [[ -d "${home_mf}/2.0.0/models_class1_presentation" || -L "${home_mf}/2.0.0" ]]; then
    printf '%s\n' "$home_mf" >"$hint"
  elif [[ -d /home/na/.local/share/mhcflurry/2.0.0/models_class1_presentation || -L /home/na/.local/share/mhcflurry/2.0.0 ]]; then
    printf '%s\n' "/home/na/.local/share/mhcflurry" >"$hint"
  fi
  [[ -f "$hint" ]] && chmod a+rw "$hint" 2>/dev/null || true

  if [[ "$fixed" -eq 0 ]]; then
    warn "未发现 MHCflurry models_class1_presentation；生产 ranking 前请运行: mhcflurry-downloads fetch models_class1_presentation"
    return 1
  fi
  return 0
}

# Copy fread fit patch into deps neo tree when present (non-destructive backup).
maybe_patch_deps_sequenza_fit() {
  local fit_r="${DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R"
  local patch_src
  patch_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/run_sequenza_fit.fread.R"
  [[ -f "$fit_r" ]] || return 0
  [[ -f "$patch_src" ]] || return 0

  if grep -q 'data.table::fread' "$fit_r" 2>/dev/null && grep -q 'assignInNamespace' "$fit_r" 2>/dev/null; then
    ok "deps neo run_sequenza_fit.R 已含 fread 补丁"
    return 0
  fi

  if [[ "${NEOAG_APPLY_SEQUENZA_FIT_PATCH:-1}" != "1" ]]; then
    warn "跳过写入 deps sequenza fit 补丁（NEOAG_APPLY_SEQUENZA_FIT_PATCH=0）"
    return 0
  fi

  cp -a "$fit_r" "${fit_r}.bak_pre_fread_$(date +%Y%m%d_%H%M%S)"
  cp -a "$patch_src" "$fit_r"
  ok "已将 fread Sequenza fit 补丁写入 ${fit_r}"
}

apply_runtime_hardening() {
  ensure_sequenza_datatable || true
  ensure_mhcflurry_layout || true
  maybe_patch_deps_sequenza_fit || true
}
