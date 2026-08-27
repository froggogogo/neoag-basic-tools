#!/usr/bin/env bash
# Runtime hardening helpers (Sequenza data.table, MHCflurry layout).
# Sourced from install.sh / install_envs.sh.

# 169-style broken r-base: exec/R linked to libiconv.so.2 + libicu*.so.75 that
# were never installed into the env. Copy from a sibling env or conda prefix.
ensure_sequenza_r_dynlibs() {
  local env_prefix="${CONDA_BASE}/envs/neoag-sequenza"
  local rbin="${env_prefix}/lib/R/bin/exec/R"
  [[ -x "$rbin" ]] || return 0
  if ldd "$rbin" 2>/dev/null | grep -q 'libiconv.so.2 => not found'; then
    log "neoag-sequenza R 缺 libiconv/icu，从同机其它 env 补共享库"
  else
    return 0
  fi
  local src="" cand
  for cand in \
    "${CONDA_BASE}/envs/neoag-fusion/lib" \
    "${CONDA_BASE}/envs/neoag-tools/lib" \
    "${CONDA_BASE}/lib"
  do
    if [[ -e "${cand}/libiconv.so.2" ]]; then src="$cand"; break; fi
  done
  if [[ -z "$src" ]]; then
    warn "未找到 libiconv.so.2 可复制来源"
    return 1
  fi
  mkdir -p "${env_prefix}/lib"
  local f
  for f in libiconv.so libiconv.so.2 libiconv.so.2.7.0 \
           libicuuc.so.75 libicuuc.so.75.1 \
           libicui18n.so.75 libicui18n.so.75.1 \
           libicudata.so.75 libicudata.so.75.1; do
    [[ -e "${src}/$f" ]] && cp -a "${src}/$f" "${env_prefix}/lib/$f"
  done
  ok "已补 neoag-sequenza libiconv/icu from ${src}"
}

ensure_sequenza_r_packages_from_gold() {
  local env_prefix="${CONDA_BASE}/envs/neoag-sequenza"
  local rscript="${env_prefix}/bin/Rscript"
  local gold="${DEPS_DIR}/packages/r_libs/sequenza_library"
  [[ -x "$rscript" ]] || return 0
  if "$rscript" -e 'suppressPackageStartupMessages(library(sequenza)); cat("OK\n")' >/dev/null 2>&1; then
    return 0
  fi
  [[ -d "$gold" ]] || return 1
  log "从金标准 R library 补 sequenza 依赖: ${gold}"
  mkdir -p "${env_prefix}/lib/R/library"
  rsync -a "$gold"/ "${env_prefix}/lib/R/library/" || return 1
  "$rscript" -e 'suppressPackageStartupMessages(library(sequenza)); cat("OK\n")' >/dev/null 2>&1
}

ensure_sequenza_datatable() {
  local env_prefix="${CONDA_BASE}/envs/neoag-sequenza"
  local rscript="${env_prefix}/bin/Rscript"
  [[ -d "$env_prefix" ]] || return 0
  [[ -x "$rscript" ]] || {
    warn "neoag-sequenza 无 Rscript，跳过 r-data.table"
    return 0
  }

  ensure_sequenza_r_dynlibs || true
  ensure_sequenza_r_packages_from_gold || true

  if "$rscript" -e 'cat(requireNamespace("data.table", quietly=TRUE), "\n")' 2>/dev/null | grep -q TRUE; then
    ok "neoag-sequenza 已具备 data.table"
    return 0
  fi

  log "安装 r-data.table 到 neoag-sequenza（Sequenza fit fread 必需）"
  ensure_dir "${DEPS_DIR}/logs" 777
  local ok_install=0
  if declare -F conda_frontend >/dev/null 2>&1; then
    if conda_frontend install -y -n neoag-sequenza --override-channels -c conda-forge r-data.table \
        >"${DEPS_DIR}/logs/r_datatable_conda.out" 2>"${DEPS_DIR}/logs/r_datatable_conda.err"; then
      ok_install=1
    fi
  elif [[ -n "${CONDA_EXE:-}" ]] && "${CONDA_EXE}" install -y -n neoag-sequenza --override-channels -c conda-forge r-data.table \
      >"${DEPS_DIR}/logs/r_datatable_conda.out" 2>"${DEPS_DIR}/logs/r_datatable_conda.err"; then
    ok_install=1
  fi
  if [[ "$ok_install" -eq 0 ]]; then
    warn "conda 安装 r-data.table 失败，尝试 R install.packages"
    if "$rscript" -e 'install.packages("data.table", repos="https://cloud.r-project.org")' \
        >"${DEPS_DIR}/logs/r_datatable_cran.out" 2>"${DEPS_DIR}/logs/r_datatable_cran.err"; then
      ok_install=1
    fi
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
  fi
  [[ -f "$hint" ]] && chmod a+rw "$hint" 2>/dev/null || true

  if [[ "$fixed" -eq 0 ]]; then
    warn "未发现 MHCflurry models_class1_presentation；生产 ranking 前请运行: mhcflurry-downloads fetch models_class1_presentation"
    return 1
  fi
  return 0
}

sequenza_skill_tools_dir() {
  echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tools/sequenza"
}

sequenza_fit_is_chromsplit() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  grep -q 'split_seqz_by_chrom' "$f" 2>/dev/null && grep -q 'assignInNamespace' "$f" 2>/dev/null
}

# Copy chrom-split fit + bam2seqz wrapper + step runner into deps.
install_sequenza_runtime_files() {
  local src dest patch_src
  src="$(sequenza_skill_tools_dir)"
  dest="${DEPS_DIR}/tools/sequenza"
  patch_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/run_sequenza_fit.fread.R"
  ensure_dir "$dest" 775
  if [[ -f "${src}/bam2seqz_nulsafe.py" ]]; then
    cp -a "${src}/bam2seqz_nulsafe.py" "${dest}/bam2seqz_nulsafe.py"
    chmod a+r "${dest}/bam2seqz_nulsafe.py" 2>/dev/null || true
  fi
  if [[ -f "${src}/run_sequenza_steps.sh" ]]; then
    cp -a "${src}/run_sequenza_steps.sh" "${dest}/run_sequenza_steps.sh"
    chmod a+rx "${dest}/run_sequenza_steps.sh" 2>/dev/null || true
  fi
  if [[ -f "$patch_src" ]]; then
    cp -a "$patch_src" "${dest}/run_sequenza_fit.R"
    chmod a+r "${dest}/run_sequenza_fit.R" 2>/dev/null || true
  fi
  ok "Sequenza 运行文件已写入 ${dest}"
}

# samtools 1.23 mpileup can emit NULs that crash sequenza-utils c_pileup.
# Gold path (sunbinbin): dedicated 1.9 binary for bam2seqz -S.
ensure_sequenza_samtools19() {
  local prefix="${CONDA_BASE:-${DEPS_DIR}/software/miniforge3}"
  local dest="${prefix}/envs/neoag-samtools19"
  local bin="${dest}/bin/samtools"
  if [[ -x "$bin" ]]; then
    ok "neoag-samtools19 已存在: $bin"
    return 0
  fi
  # Reuse sequenza env if it already is 1.9
  local sq="${prefix}/envs/neoag-sequenza/bin/samtools"
  if [[ -x "$sq" ]]; then
    local ver
    ver="$("$sq" --version 2>/dev/null | awk 'NR==1{print $2}')"
    if [[ "$ver" == 1.9* ]]; then
      ok "neoag-sequenza samtools 已是 1.9 (${ver})，不另建 neoag-samtools19"
      return 0
    fi
  fi
  [[ -n "${CONDA_EXE:-}" && -x "${CONDA_EXE}" ]] || {
    warn "无 conda，跳过 neoag-samtools19（bam2seqz 将回退 sequenza env samtools + NUL wrapper）"
    return 1
  }
  log "创建 neoag-samtools19（samtools=1.9，供 Sequenza bam2seqz mpileup）"
  ensure_dir "${DEPS_DIR}/logs" 777
  local ok_install=0
  if declare -F conda_frontend >/dev/null 2>&1; then
    if conda_frontend create -y -n neoag-samtools19 -c bioconda -c conda-forge samtools=1.9 \
        >"${DEPS_DIR}/logs/samtools19_conda.out" 2>"${DEPS_DIR}/logs/samtools19_conda.err"; then
      ok_install=1
    fi
  elif "${CONDA_EXE}" create -y -n neoag-samtools19 -c bioconda -c conda-forge samtools=1.9 \
      >"${DEPS_DIR}/logs/samtools19_conda.out" 2>"${DEPS_DIR}/logs/samtools19_conda.err"; then
    ok_install=1
  fi
  if [[ "$ok_install" -eq 1 && -x "$bin" ]]; then
    ok "neoag-samtools19 安装成功: $bin"
    return 0
  fi
  warn "neoag-samtools19 安装失败，见 ${DEPS_DIR}/logs/samtools19_conda.err"
  return 1
}

# Copy chrom-split fread fit patch into deps neo tree when present.
maybe_patch_deps_sequenza_fit() {
  local fit_r="${DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R"
  local patch_src
  patch_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/run_sequenza_fit.fread.R"
  [[ -f "$patch_src" ]] || return 0

  if sequenza_fit_is_chromsplit "$fit_r"; then
    ok "deps neo run_sequenza_fit.R 已含 chrom-split fread 补丁"
    return 0
  fi

  if [[ "${NEOAG_APPLY_SEQUENZA_FIT_PATCH:-1}" != "1" ]]; then
    warn "跳过写入 deps sequenza fit 补丁（NEOAG_APPLY_SEQUENZA_FIT_PATCH=0）"
    return 0
  fi

  if [[ -f "$fit_r" ]]; then
    cp -a "$fit_r" "${fit_r}.bak_pre_chromsplit_$(date +%Y%m%d_%H%M%S)"
  else
    ensure_dir "$(dirname "$fit_r")" 775
  fi
  cp -a "$patch_src" "$fit_r"
  ok "已将 chrom-split Sequenza fit 补丁写入 ${fit_r}"
}

# If deps BigMHC has models but no src/predict.py, copy src from fallback.
# Do not overwrite a complete deps tree.
ensure_bigmhc_predict_py() {
  local dest="${DEPS_DIR}/licenses/predictors/bigmhc"
  local fallback="${NEOAG_PRED_FALLBACK:-/mnt/zzbnew/peixunban/gl/liup/neodata4git/data/predictors}/bigmhc"
  [[ -f "${dest}/src/predict.py" ]] && return 0
  if [[ -f "${fallback}/src/predict.py" ]]; then
    ensure_dir "${dest}/src" 775
    cp -a "${fallback}/src/." "${dest}/src/"
    ok "已从 fallback 补齐 BigMHC src/ → ${dest}/src"
    return 0
  fi
  warn "BigMHC 缺 src/predict.py（${dest}）。生产会记 missing。请从完整 deps 拷贝 src/"
  return 1
}

# Verify DTU NetMHCstabpan is already inside DEPS_DIR (neoag_100T).
# Do not pull from other NAS. Seed by copying into 100T when tuning is done.
ensure_netmhcstabpan_dtu() {
  local dest="${DEPS_DIR}/licenses/predictors/netMHCstabpan"
  if [[ -x "${dest}/Linux_x86_64/bin/netMHCstabpan" && -d "${dest}/data" ]]; then
    ok "NetMHCstabpan DTU 已在 ${dest}"
    return 0
  fi
  warn "NetMHCstabpan DTU 标记未齐（${dest}）。不阻断安装；运行 skill 需要 Linux_x86_64/bin + data/。"
  return 0
}

# NetMHCpan must live under DEPS_DIR/licenses/predictors/netMHCpan (neoag_100T).
# Old .wrapper-bin hardcodes /root/neo/licensed_tools (often a zjl symlink) — rewrite portable.
ensure_netmhcpan_portable() {
  local home="${DEPS_DIR}/licenses/predictors/netMHCpan"
  local bin="${home}/Linux_x86_64/bin/netMHCpan-4.2"
  local wrap_bin="${home}/.wrapper-bin/netMHCpan-4.2"
  local front="${home}/netMHCpan"
  if [[ ! -x "$bin" ]]; then
    warn "NetMHCpan binary missing under ${home} (expected Linux_x86_64/bin/netMHCpan-4.2)"
    return 1
  fi
  ensure_dir "${home}/.wrapper-bin" 775
  ensure_dir "${home}/tmp" 777

  # Portable frontend: prefer relative BIN + host conda sysroot; never /root/neo/licensed_tools or zjl.
  cat >"$front" <<'EOF'
#!/usr/bin/env bash
# NetMHCpan 4.2 frontend — always under NETMHCPAN_HOME (neoag_100T licenses).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
export NETMHCPAN_HOME="${NETMHCPAN_HOME:-${ROOT}}"
PLATFORM_DIR="${NETMHCPAN_HOME}/Linux_$(uname -m)"
export NETMHCpan="${NETMHCpan:-${PLATFORM_DIR}}"
export TMPDIR="${NEOAG_NETMHCPAN_TMPDIR:-${NETMHCPAN_HOME}/tmp}"
mkdir -p "${TMPDIR}"

BIN="${PLATFORM_DIR}/bin/netMHCpan-4.2"
if [[ ! -x "${BIN}" ]]; then
  echo "netMHCpan binary not found under ${NETMHCPAN_HOME}" >&2
  exit 127
fi

_resolve_conda_base() {
  if [[ -n "${NEOAG_CONDA_BASE:-}" && -d "${NEOAG_CONDA_BASE}" ]]; then
    echo "${NEOAG_CONDA_BASE}"
    return 0
  fi
  local cand
  for cand in /root/neo/envs/miniforge3 /home/na/miniforge3 /root/neo/env_tool/miniforge3; do
    [[ -d "$cand" ]] && { echo "$cand"; return 0; }
  done
  conda info --base 2>/dev/null || true
}
CONDA_BASE="$(_resolve_conda_base)"
SYSROOT="${CONDA_BASE}/envs/neoag-tools/x86_64-conda-linux-gnu/sysroot"
LD_LINUX="${SYSROOT}/lib64/ld-linux-x86-64.so.2"
[[ -x "${LD_LINUX}" ]] || LD_LINUX="${SYSROOT}/lib/ld-linux-x86-64.so.2"
if [[ -n "${CONDA_BASE}" && -x "${LD_LINUX}" ]]; then
  exec "${LD_LINUX}" --library-path "${SYSROOT}/lib64:${SYSROOT}/lib" "${BIN}" "$@"
fi
exec "${BIN}" "$@"
EOF
  chmod a+rx "$front"

  # .wrapper-bin may be invoked by older callers; keep it as a thin redirect to frontend.
  cat >"$wrap_bin" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$(printf '%q' "$front")" "\$@"
EOF
  chmod a+rx "$wrap_bin"

  # Host tools/ symlink: prefer 100T home; never leave a zjl licensed_tools pointer.
  local _ips=" $(hostname -I 2>/dev/null || true) "
  local host_tools=""
  if [[ "${_ips}" == *" 10.200.65.66 "* ]]; then
    host_tools=/root/neo/envs/tools/netMHCpan
  elif [[ "${_ips}" == *" 10.200.65.169 "* ]]; then
    host_tools=/root/neo/env_tool/tools/netMHCpan
  elif [[ "${_ips}" == *" 10.200.50.134 "* ]]; then
    host_tools=""
  fi
  if [[ -n "$host_tools" ]]; then
    mkdir -p "$(dirname "$host_tools")"
    ln -sfn "$home" "$host_tools"
    ok "host tools/netMHCpan -> ${home}"
  fi

  if NETMHCPAN_HOME="$home" NEOAG_CONDA_BASE="${NEOAG_CONDA_BASE:-${CONDA_BASE:-}}" \
       "$front" -h >/dev/null 2>&1; then
    ok "NetMHCpan portable OK under ${home}"
    return 0
  fi
  warn "NetMHCpan smoke failed under ${home}"
  return 1
}

# mhcflurry imports Class2Pair from mhcgnomes. Some installs omit the re-export or
# only expose Pair — patch __init__.py so SNAF binding prediction works on any host.
ensure_mhcgnomes_class2pair_compat() {
  local py="${CONDA_BASE}/envs/neoag-snaf/bin/python"
  [[ -x "$py" ]] || return 0
  if "$py" -c "from mhcgnomes import Class2Pair" >/dev/null 2>&1; then
    ok "mhcgnomes.Class2Pair import OK"
    return 0
  fi
  log "patching mhcgnomes Class2Pair compatibility for mhcflurry"
  if ! "$py" - <<'PY'
import importlib
from pathlib import Path
import mhcgnomes

init = Path(mhcgnomes.__file__)
text = init.read_text(encoding="utf-8")
marker = "# neoag Class2Pair compat shim"
if marker not in text:
    text += (
        "\n" + marker + "\n"
        "try:\n"
        "    from .class2_pair import Class2Pair  # noqa: F401\n"
        "except Exception:\n"
        "    try:\n"
        "        from .pair import Pair as Class2Pair  # noqa: F401\n"
        "    except Exception:\n"
        "        pass\n"
        "if 'Class2Pair' in globals():\n"
        "    __all__ = list(__all__) + (['Class2Pair'] if 'Class2Pair' not in __all__ else [])\n"
    )
    bak = init.with_suffix(init.suffix + ".bak_pre_class2pair")
    if not bak.exists():
        bak.write_text(init.read_text(encoding="utf-8"), encoding="utf-8")
    init.write_text(text, encoding="utf-8")
importlib.reload(mhcgnomes)
from mhcgnomes import Class2Pair  # noqa: F401
print("Class2Pair OK", Class2Pair)
PY
  then
    warn "mhcgnomes Class2Pair shim script failed"
    return 1
  fi
  if "$py" -c "from mhcgnomes import Class2Pair; import mhcflurry" >/dev/null 2>&1; then
    ok "mhcgnomes Class2Pair compat + mhcflurry OK"
    return 0
  fi
  warn "mhcgnomes Class2Pair still broken after compat patch"
  return 1
}

apply_runtime_hardening() {
  ensure_sequenza_r_dynlibs || true
  ensure_sequenza_datatable || true
  ensure_sequenza_samtools19 || true
  install_sequenza_runtime_files || true
  maybe_patch_deps_sequenza_fit || true
  ensure_mhcflurry_layout || true
  ensure_mhcgnomes_class2pair_compat || true
  ensure_bigmhc_predict_py || true
  ensure_netmhcstabpan_dtu || true
  ensure_netmhcpan_portable || true
}
