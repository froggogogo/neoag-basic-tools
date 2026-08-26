#!/usr/bin/env bash
# Fill missing conda envs + gold Sequenza/pVAC files on THIS host.
# Uses host miniforge (134 /home/na, 66 /root/neo/envs, 169 /root/neo/env_tool).
# Does NOT install conda onto OSS neoag_100T (FUSE is a bad conda prefix).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/conda.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/install_envs.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/runtime_hardening.sh"

DEPS_DIR="${DEPS_DIR:-${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}}"
export DEPS_DIR ALLOW_ROOT_CONDA="${ALLOW_ROOT_CONDA:-1}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"
YES="${YES:-1}"
PACK_DIR="${PACK_DIR:-${DEPS_DIR}/packages/conda_packs}"

install_skill_files_into_deps() {
  ensure_dir "${DEPS_DIR}/configs" 777
  ensure_dir "${DEPS_DIR}/tools/sequenza" 777
  ensure_dir "${DEPS_DIR}/tools/pvac" 777
  ensure_dir "${DEPS_DIR}/logs" 777
  ensure_dir "${DEPS_DIR}/packages/conda_pkgs" 1777
  ensure_dir "${PACK_DIR}" 777
  ensure_dir "${DEPS_DIR}/manifests" 777

  cp -f "${SCRIPT_DIR}/lib/site_runtime.sh" "${DEPS_DIR}/configs/lib_site_runtime.sh"
  cp -f "${SCRIPT_DIR}/lib/bootstrap_case.sh" "${DEPS_DIR}/configs/bootstrap_case.sh"
  chmod a+r "${DEPS_DIR}/configs/"*.sh

  local fit_src="${SCRIPT_DIR}/patches/run_sequenza_fit.fread.R"
  if [[ -f "$fit_src" ]]; then
    cp -f "$fit_src" "${DEPS_DIR}/tools/sequenza/run_sequenza_fit.R"
    if [[ -f "${DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R" ]]; then
      cp -f "$fit_src" "${DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R"
    fi
  fi
  cp -f "${SCRIPT_DIR}/tools/sequenza/bam2seqz_nulsafe.py" "${DEPS_DIR}/tools/sequenza/"
  cp -f "${SCRIPT_DIR}/tools/sequenza/run_sequenza_steps.sh" "${DEPS_DIR}/tools/sequenza/"
  chmod a+rx "${DEPS_DIR}/tools/sequenza/"* || true

  cp -f "${SCRIPT_DIR}/tools/pvac/pvacsplice_run_geneid_fix.py" "${DEPS_DIR}/tools/pvac/"
  cp -f "${SCRIPT_DIR}/tools/pvac/hla_alleles_csv.sh" "${DEPS_DIR}/tools/pvac/"
  chmod a+rx "${DEPS_DIR}/tools/pvac/"* || true
}

write_site_env() {
  local out="${DEPS_DIR}/configs/site.env.sh"
  cat >"$out" <<'EOF'
#!/usr/bin/env bash
# Portable site environment for 134 / 66 / 169.
# Usage: source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
export NEOAG_BASIC_DEPS_DIR="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
# shellcheck disable=SC1090
source "${NEOAG_BASIC_DEPS_DIR}/configs/lib_site_runtime.sh"
neoag_site_activate
EOF
  chmod a+rwx "$out" 2>/dev/null || chmod a+rw "$out" || true
  ok "wrote ${out}"
}

env_has_bin() {
  local envdir="$1" bin="$2"
  [[ -x "${envdir}/bin/${bin}" ]]
}

env_is_broken_fusion() {
  local envdir="$1"
  [[ -d "$envdir" ]] || return 0
  env_has_bin "$envdir" STAR && return 1
  return 0
}

unpack_conda_pack() {
  local name="$1"
  local dest="${CONDA_BASE}/envs/${name}"
  local pack=""
  local cand
  for cand in \
    "${PACK_DIR}/${name}.tar.gz" \
    "${PACK_DIR}/${name}.tar.zst" \
    "${PACK_DIR}/${name}.tar.bz2"
  do
    [[ -s "$cand" ]] && pack="$cand" && break
  done
  [[ -n "$pack" ]] || return 1
  log "unpack conda-pack ${name} <- ${pack}"
  mkdir -p "$dest"
  case "$pack" in
    *.tar.gz) tar -xzf "$pack" -C "$dest" ;;
    *.tar.zst) tar --use-compress-program=zstd -xf "$pack" -C "$dest" ;;
    *.tar.bz2) tar -xjf "$pack" -C "$dest" ;;
    *) tar -xf "$pack" -C "$dest" ;;
  esac
  if [[ -x "${dest}/bin/conda-unpack" ]]; then
    # R-only envs (e.g. neoag-ascat) ship without python; use host miniforge python.
    if ! "${dest}/bin/conda-unpack" 2>/dev/null; then
      if [[ -x "${CONDA_BASE}/bin/python" ]]; then
        "${CONDA_BASE}/bin/python" "${dest}/bin/conda-unpack" || true
      fi
    fi
  fi
  ok "unpacked ${name} -> ${dest}"
}

ensure_ascat() {
  local envdir="${CONDA_BASE}/envs/neoag-ascat"
  if [[ -x "${envdir}/bin/Rscript" ]] && \
     "${envdir}/bin/Rscript" -e 'library(ASCAT); cat("OK\n")' >/dev/null 2>&1; then
    ok "neoag-ascat ASCAT library OK"
    return 0
  fi
  warn "neoag-ascat missing or broken (134 paths?) — unpack from conda-pack"
  rm -rf "$envdir"
  if unpack_conda_pack neoag-ascat && \
     "${envdir}/bin/Rscript" -e 'library(ASCAT); cat("OK\n")' >/dev/null 2>&1; then
    ok "neoag-ascat restored"
    return 0
  fi
  warn "neoag-ascat still broken after unpack"
  return 1
}

ensure_samtools19() {
  local envdir="${CONDA_BASE}/envs/neoag-samtools19"
  if [[ -x "${envdir}/bin/samtools" ]]; then
    ok "neoag-samtools19 already present"
    return 0
  fi
  if unpack_conda_pack neoag-samtools19 && [[ -x "${envdir}/bin/samtools" ]]; then
    return 0
  fi
  log "creating neoag-samtools19 (samtools=1.9)"
  if conda_frontend create -y -n neoag-samtools19 -c bioconda -c conda-forge samtools=1.9; then
    ok "neoag-samtools19 created"
  else
    warn "neoag-samtools19 create failed"
    return 1
  fi
}

ensure_star_in_fusion() {
  local envdir="${CONDA_BASE}/envs/neoag-fusion"
  if env_is_broken_fusion "$envdir"; then
    warn "neoag-fusion missing STAR — try unpack, then install STAR into existing env"
    if unpack_conda_pack neoag-fusion && [[ -x "${envdir}/bin/STAR" ]]; then
      ok "neoag-fusion restored from pack"
      return 0
    fi
    if [[ -d "$envdir" ]]; then
      log "installing STAR/samtools into existing neoag-fusion"
      conda_frontend install -y -n neoag-fusion --override-channels -c bioconda -c conda-forge star samtools || true
    elif [[ "${NEOAG_ENV_FILL:-auto}" == "create" && -f "${DEPS_DIR}/src/neo/conda/env.neoag-fusion.yml" ]]; then
      conda_frontend env create -y -n neoag-fusion -f "${DEPS_DIR}/src/neo/conda/env.neoag-fusion.yml" || warn "fusion recreate failed"
    else
      warn "skip recreating neoag-fusion from yml (waiting for conda-pack)"
      return 1
    fi
  fi
  local star="${envdir}/bin/STAR"
  [[ -x "$star" ]] && { ok "STAR present in neoag-fusion"; return 0; }
  [[ -d "$envdir" ]] || { warn "neoag-fusion missing"; return 1; }
  log "installing STAR into neoag-fusion"
  conda_frontend install -y -n neoag-fusion --override-channels -c bioconda -c conda-forge star || warn "STAR install failed"
}

ensure_salmon_cpp() {
  local envdir="${CONDA_BASE}/envs/neoag-salmon-cpp"
  if [[ -x "${envdir}/bin/salmon" ]]; then
    ok "neoag-salmon-cpp present"
    return 0
  fi
  if [[ -x "${CONDA_BASE}/envs/neoag-fusion/bin/salmon" ]]; then
    ok "salmon available in neoag-fusion (salmon-cpp optional)"
  fi
  if unpack_conda_pack neoag-salmon-cpp && [[ -x "${envdir}/bin/salmon" ]]; then
    return 0
  fi
  log "creating neoag-salmon-cpp (salmon=1.10.3)"
  conda_frontend create -y -n neoag-salmon-cpp -c bioconda -c conda-forge salmon=1.10.3 || warn "salmon-cpp create failed"
}

# SpecHLA conda prefix is NOT named neoag-*; unpack beside host miniforge envs.
ensure_spechla_env() {
  local dest="${CONDA_BASE}/envs/spechla_env"
  local home="${DEPS_DIR}/tools/neodata_tools/SpecHLA"
  # Shared deps layout: expose script/bin/db expected by run_spechla*.sh
  if [[ -d "${home}/source/script" && ! -e "${home}/script" ]]; then
    ln -sfn source/script "${home}/script" 2>/dev/null || true
  fi
  if [[ -d "${home}/source/bin" && ! -e "${home}/bin" ]]; then
    ln -sfn source/bin "${home}/bin" 2>/dev/null || true
  fi
  if [[ ! -e "${home}/db" && -d "${DEPS_DIR}/refs/hla/spechla/db" ]]; then
    ln -sfn "${DEPS_DIR}/refs/hla/spechla/db" "${home}/db" 2>/dev/null || true
  fi
  if [[ -d "${dest}/bin" ]]; then
    ok "spechla_env already present -> ${dest}"
    export SPECHLA_ENV="${dest}"
    return 0
  fi
  # Prefer existing gold prefix on THIS host only
  local gold
  local golds=()
  _ips=" $(hostname -I 2>/dev/null || true) "
  if [[ "${_ips}" == *" 10.200.50.134 "* ]]; then
    golds+=(/home/na/project/neoantigen/neoag_event_pipeline_v03_rc/tools/SpecHLA/spechla_env)
  elif [[ "${_ips}" == *" 10.200.65.66 "* ]]; then
    golds+=(/root/neo/envs/tools/SpecHLA/spechla_env)
  elif [[ "${_ips}" == *" 10.200.65.169 "* ]]; then
    golds+=(/root/neo/env_tool/tools/SpecHLA/spechla_env)
  fi
  for gold in "${golds[@]}"; do
    if [[ -d "${gold}/bin" ]]; then
      ok "using gold spechla_env -> ${gold}"
      export SPECHLA_ENV="${gold}"
      return 0
    fi
  done
  if unpack_conda_pack spechla_env && [[ -d "${dest}/bin" ]]; then
    export SPECHLA_ENV="${dest}"
    return 0
  fi
  warn "spechla_env missing (need conda-pack spechla_env.tar.gz in ${PACK_DIR} or gold tree)"
  return 1
}

LARGE_ENVS="neoag-tools neoag-fusion neoag-splicemutr neoag-snaf neoag-pvactools711 neoag-vep neoag-gatk neoag-optitype"

is_large_env() {
  local n="$1"
  [[ " ${LARGE_ENVS} " == *" ${n} "* ]]
}

ensure_env_named() {
  local name="$1"
  local envdir="${CONDA_BASE}/envs/${name}"
  local yml="${DEPS_DIR}/src/neo/conda/env.${name}.yml"
  if [[ "$name" == "neoag-fusion" ]] && env_is_broken_fusion "$envdir"; then
    warn "${name} exists but looks broken (no STAR)"
  elif [[ -d "$envdir" ]]; then
    ok "env exists: ${name}"
    return 0
  fi
  if unpack_conda_pack "$name" && [[ -d "$envdir" ]]; then
    return 0
  fi
  if is_large_env "$name" && [[ "${NEOAG_ENV_FILL:-auto}" != "create" ]]; then
    warn "skip creating large env ${name} from yml (waiting for conda-pack). Override: NEOAG_ENV_FILL=create"
    return 1
  fi
  if [[ ! -f "$yml" ]]; then
    warn "no yaml and no pack for ${name}"
    return 1
  fi
  log "creating ${name} from ${yml} (this can take a long time)"
  conda_frontend env create -y -n "$name" -f "$yml"
}

copy_tool_tree_if_missing() {
  local name="$1"
  shift
  local dest="${DEPS_DIR}/tools/${name}"
  if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null || true)" ]]; then
    ok "deps tools/${name} present"
    return 0
  fi
  local src
  for src in "$@"; do
    [[ -d "$src" ]] || continue
    log "copy tool tree ${name} <- ${src}"
    mkdir -p "$dest"
    rsync -a --exclude '.git' "$src"/ "$dest"/ || continue
    chmod -R a+rX "$dest" 2>/dev/null || true
    ok "copied ${name} into deps/tools"
    return 0
  done
  warn "no local ${name} tree to copy into deps"
  return 1
}

ensure_mhcflurry_shim() {
  local mf
  local mfs=(
    "${HOME}/.local/share/mhcflurry"
    /root/.local/share/mhcflurry
    "${DEPS_DIR}/packages/mhcflurry_data"
  )
  local _ips=" $(hostname -I 2>/dev/null || true) "
  if [[ "${_ips}" == *" 10.200.50.134 "* ]]; then
    mfs+=(/home/na/.local/share/mhcflurry)
  fi
  for mf in "${mfs[@]}"
  do
    [[ -d "$mf" ]] || continue
    if [[ -d "${mf}/4/2.0.0/models_class1_presentation" && ! -e "${mf}/2.0.0" ]]; then
      ln -sfn "${mf}/4/2.0.0" "${mf}/2.0.0"
      ok "MHCflurry shim ${mf}/2.0.0 -> 4/2.0.0"
    fi
  done
  if declare -F ensure_mhcflurry_layout >/dev/null; then
    ensure_mhcflurry_layout || true
  fi
}

# LOHHLA uses neoag-fusion Rscript. Env may have STAR but miss optparse/data.table (66).
# Prefer replace-from conda-pack (134 gold) over piecemeal installs.
env_fusion_lohhla_r_ok() {
  local envdir="${1:-${CONDA_BASE}/envs/neoag-fusion}"
  local rscript="${envdir}/bin/Rscript"
  [[ -x "$rscript" ]] || return 1
  local pkg
  for pkg in optparse data.table; do
    "$rscript" -e "cat(requireNamespace('${pkg}', quietly=TRUE))" 2>/dev/null | grep -q TRUE || return 1
  done
  return 0
}

ensure_fusion_lohhla_rpkgs() {
  local envdir="${CONDA_BASE}/envs/neoag-fusion"
  if env_fusion_lohhla_r_ok "$envdir"; then
    ok "neoag-fusion LOHHLA R (optparse/data.table) OK"
    return 0
  fi
  warn "neoag-fusion missing LOHHLA R deps — replace from conda-pack (134 gold)"
  local bak="${envdir}.bak_pre_lohhla_$(date +%Y%m%d_%H%M%S)"
  if [[ -d "$envdir" ]]; then
    mv -f "$envdir" "$bak"
    log "backed up broken neoag-fusion -> ${bak}"
  fi
  if unpack_conda_pack neoag-fusion && env_fusion_lohhla_r_ok "$envdir"; then
    ok "neoag-fusion restored from pack with LOHHLA R pkgs"
    # Keep STAR usable if pack somehow lacks it
    ensure_star_in_fusion || true
    return 0
  fi
  # Restore backup if unpack failed
  if [[ ! -d "$envdir" && -d "$bak" ]]; then
    mv -f "$bak" "$envdir"
    warn "unpack failed; restored ${bak}"
  fi
  warn "neoag-fusion still missing LOHHLA R after conda-pack"
  return 1
}

main() {
  install_skill_files_into_deps
  write_site_env

  if ! discover_conda; then
    die "NO_CONDA" "本机没有可用 conda。134=/home/na/miniforge3 66=/root/neo/envs/miniforge3 169=/root/neo/env_tool/miniforge3"
  fi
  export CONDA_PKGS_DIRS="${CONDA_BASE}/pkgs"
  mkdir -p "${CONDA_PKGS_DIRS}"

  # shellcheck disable=SC1090
  NEOAG_SITE_QUIET=1 source "${DEPS_DIR}/configs/site.env.sh" || true

  ensure_samtools19 || true
  ensure_star_in_fusion || true
  ensure_fusion_lohhla_rpkgs || true
  ensure_salmon_cpp || true
  ensure_spechla_env || true
  ensure_ascat || true

  local name
  for name in neoag-tools neoag-fusion neoag-splice neoag-splicemutr neoag-sequenza neoag-vep neoag-gatk neoag-ascat neoag-snaf neoag-optitype neoag-pvactools711; do
    ensure_env_named "$name" || true
  done

  # Re-check after ensure_env_named (may have left a STAR-only broken fusion)
  ensure_fusion_lohhla_rpkgs || true

  if [[ -x "${DEPS_DIR}/src/neo/scripts/install_optitype.sh" ]] && [[ ! -d "${CONDA_BASE}/envs/neoag-optitype" ]]; then
    log "running install_optitype.sh"
    NEOAG_CONDA_BASE="${CONDA_BASE}" bash "${DEPS_DIR}/src/neo/scripts/install_optitype.sh" || warn "optitype install failed"
  fi

  if [[ -d "${CONDA_BASE}/envs/neoag-splicemutr" ]] && declare -F ensure_splicemutr_genome_pkgs >/dev/null; then
    ensure_splicemutr_genome_pkgs || true
  fi
  if declare -F ensure_sequenza_datatable >/dev/null; then
    ensure_sequenza_datatable || true
  fi
  ensure_mhcflurry_shim || true
  if declare -F ensure_mhcgnomes_class2pair_compat >/dev/null; then
    ensure_mhcgnomes_class2pair_compat || true
  elif declare -F ensure_mhcgnomes_class2pair_shim >/dev/null; then
    ensure_mhcgnomes_class2pair_shim || true
  fi

  _ips=" $(hostname -I 2>/dev/null || true) "
  if [[ "${_ips}" == *" 10.200.65.66 "* ]]; then
    copy_tool_tree_if_missing EasyFuse /root/neo/envs/tools/EasyFuse || true
    copy_tool_tree_if_missing STAR-Fusion /root/neo/envs/tools/STAR-Fusion || true
  elif [[ "${_ips}" == *" 10.200.65.169 "* ]]; then
    copy_tool_tree_if_missing EasyFuse /root/neo/env_tool/tools/EasyFuse || true
    copy_tool_tree_if_missing STAR-Fusion /root/neo/env_tool/tools/STAR-Fusion || true
  elif [[ "${_ips}" == *" 10.200.50.134 "* ]]; then
    copy_tool_tree_if_missing EasyFuse \
      /home/na/project/neoantigen/neoag_event_pipeline_v03_rc/tools/EasyFuse || true
    copy_tool_tree_if_missing STAR-Fusion \
      /home/na/project/neoantigen/neoag_event_pipeline_v03_rc_artifact_quarantine_20260622_091158/tools/STAR-Fusion || true
  fi

  local host_report="${DEPS_DIR}/manifests/host_verify_$(hostname -s 2>/dev/null || hostname).tsv"
  if [[ -x "${SCRIPT_DIR}/host_verify.sh" ]]; then
    bash "${SCRIPT_DIR}/host_verify.sh" >"$host_report" 2>&1 || true
    log "host verify: ${host_report}"
  fi

  ok "ensure_host_runtime finished on $(hostname). source ${DEPS_DIR}/configs/site.env.sh"
}

main "$@"
