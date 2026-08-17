#!/usr/bin/env bash
# Sync assets from asset-source into DEPS_DIR (parameterized, no machine hardcode)

# Relative mappings: SRC_REL -> DEPS_REL
# Source root = ASSET_SOURCE (default neodata4git)
declare -a ASSET_MAP=(
  "data/ref/hg38|refs/hg38"
  "data/ref/ctat|refs/ctat"
  "data/rna|refs/rna"
  "data/hla|refs/hla"
  "data/vep|refs/vep"
  "data/easyfuse|refs/easyfuse"
  "data/facets|refs/facets"
  "data/hmf|refs/hmf"
  "data/lohhla|refs/lohhla"
  "data/ascat|refs/ascat"
  "data/sequenza|refs/sequenza"
  "data/snaf|refs/snaf"
  "data/normal|refs/normal"
  "data/sample_identity|refs/sample_identity"
  "data/predictors|licenses/predictors"
  "tools|tools/neodata_tools"
  "work/vep_plugins|work/vep_plugins"
)

# Probe that a path is readable by the installing user (not just -e).
asset_readable() {
  local p="$1"
  if [[ -L "$p" ]]; then
    [[ -e "$p" ]] || return 1
  fi
  if [[ -d "$p" ]]; then
    # directory: must be listable and have at least one readable child (or empty ok if listable)
    [[ -r "$p" && -x "$p" ]] || return 1
    # try reading one entry if present
    local sample
    sample="$(find "$p" -maxdepth 2 -type f 2>/dev/null | head -1 || true)"
    if [[ -n "$sample" ]]; then
      [[ -r "$sample" ]] || return 1
      # byte-level open check
      head -c 1 "$sample" >/dev/null 2>&1 || return 1
    fi
    return 0
  fi
  if [[ -f "$p" ]]; then
    [[ -r "$p" ]] || return 1
    head -c 1 "$p" >/dev/null 2>&1 || return 1
    return 0
  fi
  return 1
}

# True if path is a symlink whose ultimate target is outside DEPS_DIR.
is_external_symlink() {
  local p="$1"
  [[ -L "$p" ]] || return 1
  local target resolved deps
  target="$(readlink "$p" || true)"
  [[ -n "$target" ]] || return 0
  if [[ "$target" != /* ]]; then
    target="$(cd "$(dirname "$p")" && pwd -P)/${target}"
  fi
  if [[ -e "$target" ]]; then
    resolved="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target")"
  else
    resolved="$target"
  fi
  deps="$(cd "${DEPS_DIR}" 2>/dev/null && pwd -P || echo "${DEPS_DIR}")"
  [[ "$resolved" != "$deps" && "$resolved" != "$deps"/* ]]
}

materialize_or_remove_dst() {
  # Prepare dst for a fresh sync: remove empty dirs / replace external symlinks when copying.
  local dst="$1"
  local mode="$2"
  local force="${FORCE_RESYNC:-0}"

  if [[ -L "$dst" ]]; then
    if [[ "$mode" == "copy" || "$force" == "1" ]]; then
      warn "目标是软链，将拆除以便 ${mode}: $dst -> $(readlink "$dst" 2>/dev/null || echo '?')"
      rm -f "$dst"
      return 0
    fi
    # symlink mode: keep if already correct (handled by caller)
    return 0
  fi

  if [[ -d "$dst" && -z "$(find "$dst" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]]; then
    rmdir "$dst" 2>/dev/null || true
  fi
}

sync_one() {
  local src="$1"
  local dst="$2"
  local mode="$3" # symlink|copy

  if [[ ! -e "$src" ]]; then
    warn "资产缺失，跳过: $src"
    echo -e "${dst}\t${src}\tMISSING\t-" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
    return 1
  fi

  if ! asset_readable "$src"; then
    warn "资产存在但当前用户不可读: $src"
    echo -e "${dst}\t${src}\tUNREADABLE_SRC\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
    if [[ "$mode" == "symlink" ]]; then
      err "reason=ASSET_UNREADABLE"
      err "源目录不可读，软链装上后运行机也无法用。请换可读账号、修权限，或改用 --sync-mode copy（仍需要安装期可读才能复制）。"
      return 1
    fi
    return 1
  fi

  ensure_dir "$(dirname "$dst")" 777
  materialize_or_remove_dst "$dst" "$mode"

  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ -L "$dst" ]]; then
      local cur
      cur="$(readlink "$dst" || true)"
      if [[ "$cur" == "$src" && "${FORCE_RESYNC:-0}" != "1" ]]; then
        if asset_readable "$dst"; then
          log "已存在可读软链，跳过: $dst"
          echo -e "${dst}\t${src}\tEXISTS_SYMLINK_OK\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
          return 0
        fi
        warn "已有软链但不可读（目标权限/挂载问题）: $dst -> $cur"
        if [[ "$mode" == "copy" ]]; then
          rm -f "$dst"
        else
          echo -e "${dst}\t${src}\tSYMLINK_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
          return 1
        fi
      else
        warn "已有不同/过期软链 ($cur)，将替换"
        rm -f "$dst"
      fi
    elif [[ -d "$dst" ]]; then
      if [[ "${FORCE_RESYNC:-0}" == "1" && "$mode" == "copy" ]]; then
        warn "FORCE_RESYNC: rsync 覆盖目录 $dst"
      else
        # non-empty real directory — treat as already materialized
        if asset_readable "$dst"; then
          log "目标已是可读目录，跳过: $dst（覆盖请加 --force-resync）"
          echo -e "${dst}\t${src}\tEXISTS_DIR\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
          return 0
        fi
        warn "目标目录存在但不可读: $dst"
        echo -e "${dst}\t${src}\tDIR_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
        return 1
      fi
    else
      warn "目标已存在文件，跳过: $dst"
      echo -e "${dst}\t${src}\tEXISTS_FILE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
      return 0
    fi
  fi

  case "$mode" in
    symlink)
      ln -s "$src" "$dst" || die "SYMLINK_FAILED" "无法链接 $src -> $dst"
      if ! asset_readable "$dst"; then
        rm -f "$dst"
        echo -e "${dst}\t${src}\tSYMLINK_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
        err "reason=SYMLINK_UNREADABLE"
        err "软链已建但不可读: $dst -> $src。改用 --sync-mode copy，或修复源权限/挂载。"
        return 1
      fi
      ok "symlink $dst -> $src"
      echo -e "${dst}\t${src}\tSYMLINK\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
      ;;
    copy)
      require_cmd rsync
      log "rsync copy: $src -> $dst （大目录可能较久）"
      if [[ -d "$src" ]]; then
        ensure_dir "$dst" 777
        rsync -a --info=progress2 "$src"/ "$dst"/ || die "RSYNC_FAILED" "复制失败: $src"
      else
        rsync -a "$src" "$dst" || die "RSYNC_FAILED" "复制失败: $src"
      fi
      chmod -R a+rwX "$dst" 2>/dev/null || true
      if ! asset_readable "$dst"; then
        echo -e "${dst}\t${src}\tCOPY_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
        die "COPY_UNREADABLE" "复制后仍不可读: $dst（检查 deps-dir 权限）"
      fi
      ok "copied $dst"
      echo -e "${dst}\t${src}\tCOPY\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
      ;;
    *)
      die "BAD_SYNC_MODE" "未知 --sync-mode: $mode（symlink|copy）"
      ;;
  esac
  return 0
}

resolve_sync_mode() {
  # auto: prefer copy for portable deps; allow symlink only if source readable AND user asked symlink.
  case "${SYNC_MODE}" in
    copy|symlink) ;;
    auto)
      warn "sync-mode=auto → 使用 copy（资产落入 deps，不依赖 asset-source 长期可读）"
      SYNC_MODE="copy"
      export SYNC_MODE
      ;;
    *)
      die "BAD_SYNC_MODE" "未知 --sync-mode: ${SYNC_MODE}（copy|symlink|auto）"
      ;;
  esac
}

deps_dest_ready() {
  local dest_rel="$1"
  local dst="${DEPS_DIR}/${dest_rel}"
  [[ "${FORCE_RESYNC:-0}" == "1" ]] && return 1
  [[ -e "$dst" || -L "$dst" ]] || return 1
  [[ -L "$dst" ]] && is_external_symlink "$dst" && return 1
  asset_readable "$dst"
}

sync_assets() {
  resolve_sync_mode
  local mode="${SYNC_MODE}"
  local src_root="${ASSET_SOURCE}"
  ensure_dir "${DEPS_DIR}" 777
  ensure_dir "${DEPS_DIR}/manifests" 777
  printf 'dest\tsource\tstatus\tmode\n' >"${DEPS_DIR}/manifests/sync_assets.tsv"

  local entry dest_rel
  local need_source=0
  if [[ "${FORCE_RESYNC:-0}" == "1" ]]; then
    need_source=1
  else
    for entry in "${ASSET_MAP[@]}"; do
      dest_rel="${entry##*|}"
      if ! deps_dest_ready "$dest_rel"; then
        need_source=1
        break
      fi
    done
  fi

  if [[ "$need_source" != "1" ]]; then
    log "deps 资产已齐且可读，跳过 asset-source（不需要 zjl）"
  elif [[ "$mode" == "symlink" ]]; then
    require_mount_prefix "$src_root" "asset-source"
    warn "sync-mode=symlink：deps 里的 refs 指向 ${src_root}"
    warn "风险：其它只挂 deps 盘的机器若读不到 asset-source，运行会失败。生产请用 --sync-mode copy。"
    if ! asset_readable "$src_root"; then
      die "ASSET_SOURCE_UNREADABLE" \
        "asset-source 不可读: ${src_root}。无法建可用软链。请修权限，或改用能读该盘的账号 / --sync-mode copy（仅缺项灌库时需要）。"
    fi
  else
    log "sync-mode=copy：缺项将从 asset-source 复制进 ${DEPS_DIR}"
    require_mount_prefix "$src_root" "asset-source"
    if ! asset_readable "$src_root"; then
      die "ASSET_SOURCE_UNREADABLE" \
        "deps 仍缺资产，且 asset-source 不可读: ${src_root}。请挂载可读的 zjl，或等共享 deps 灌完后再装。"
    fi
  fi

  local entry src_rel dest_rel src dst
  local fail=0
  for entry in "${ASSET_MAP[@]}"; do
    src_rel="${entry%%|*}"
    dest_rel="${entry##*|}"
    src="${src_root}/${src_rel}"
    dst="${DEPS_DIR}/${dest_rel}"
    if ! sync_one "$src" "$dst" "$mode"; then
      fail=$((fail + 1))
    fi
  done

  # neo tree: prefer existing deps snapshot (skill is independent of neo git).
  # --neo-src only for bootstrap machines that still need to seed the snapshot once.
  if [[ -n "${NEO_SRC}" && -d "${NEO_SRC}" ]]; then
    local neo_dst="${DEPS_DIR}/src/neo"
    if [[ -L "$neo_dst" && "$mode" == "copy" ]]; then
      warn "拆除 neo 软链以便 copy: $neo_dst"
      rm -f "$neo_dst"
    fi
    if [[ ! -e "$neo_dst" ]]; then
      if [[ "$mode" == "symlink" ]]; then
        ln -s "$(cd "$NEO_SRC" && pwd -P)" "$neo_dst"
        ok "symlink neo src -> $neo_dst"
      else
        require_cmd rsync
        ensure_dir "$neo_dst" 777
        rsync -a --exclude '.git' "${NEO_SRC}/" "${neo_dst}/"
        ok "copied neo src -> $neo_dst"
      fi
    elif [[ "${FORCE_RESYNC:-0}" == "1" && "$mode" == "copy" && ! -L "$neo_dst" ]]; then
      require_cmd rsync
      rsync -a --exclude '.git' "${NEO_SRC}/" "${neo_dst}/"
      ok "force-resync neo src -> $neo_dst"
    else
      ok "沿用已有 deps 安装切片: $neo_dst（无需 neo git）"
    fi
  elif [[ -d "${DEPS_DIR}/src/neo" ]]; then
    ok "沿用已有 deps 安装切片: ${DEPS_DIR}/src/neo（无需 --neo-src / neo git）"
  else
    warn "deps 尚无 src/neo 安装切片。请使用已预置切片的共享 deps，或用 --neo-src 灌入一次。"
  fi

  chmod a+rw "${DEPS_DIR}/manifests/sync_assets.tsv" 2>/dev/null || true
  if [[ "$fail" -gt 0 ]]; then
    warn "有 ${fail} 项资产同步失败（见 manifests/sync_assets.tsv）。"
    if [[ "${CONTINUE_ON_ERROR:-0}" != "1" ]]; then
      die "SYNC_INCOMPLETE" \
        "${fail} 项资产未就绪。加 --continue-on-error 可继续并靠 verify 标红；或修权限后重跑 --mode sync。"
    fi
  fi
  ok "资产同步完成（mode=${mode}）"
}

render_site_env() {
  local out="${DEPS_DIR}/configs/site.env.sh"
  local conda_base="${CONDA_BASE:-${DEPS_DIR}/software/miniforge3}"

  refresh_easyfuse_capability
  local ef_supported="${NEOAG_EASYFUSE_SUPPORTED}"
  local ef_reason="${NEOAG_EASYFUSE_SKIP_REASON}"

  if [[ "${conda_base}" != "${DEPS_DIR}"* ]]; then
    warn "当前 Conda 不在 deps-dir 内: ${conda_base}"
    warn "一键可移植安装请用: --one-shot（会优先 ${DEPS_DIR}/software/miniforge3）"
  fi

  cat >"$out" <<EOF
#!/usr/bin/env bash
# Auto-generated by neoag-basic-tools-install ${NEOAG_INSTALL_VERSION}
# Machine-portable site environment — all runtime paths under DEPS_DIR.
# Usage: source ${out}

export NEOAG_BASIC_DEPS_DIR="${DEPS_DIR}"
export NEODATA_ROOT="\${NEOAG_BASIC_DEPS_DIR}"
export NEOAG_TOOLS_ROOT="\${NEOAG_BASIC_DEPS_DIR}"

# Code
export NEOAG_ROOT="\${NEOAG_BASIC_DEPS_DIR}/src/neo"
export PYTHONPATH="\${NEOAG_ROOT}/src:\${PYTHONPATH:-}"

# Conda (local or shared under deps)
export NEOAG_CONDA_BASE="${conda_base}"
export CONDA_EXE="\${NEOAG_CONDA_BASE}/bin/conda"
export PATH="\${NEOAG_CONDA_BASE}/bin:\${NEOAG_BASIC_DEPS_DIR}/tools/neodata_tools/bin:\${PATH:-}"

# References (centralized)
export NEOAG_SHARED_REF_DIR="\${NEOAG_BASIC_DEPS_DIR}/refs"
export NEOAG_REFERENCE_FASTA="\${NEOAG_BASIC_DEPS_DIR}/refs/hg38/Homo_sapiens_assembly38.fasta"
export REF_FASTA="\${NEOAG_REFERENCE_FASTA}"
export NEOAG_VEP_CACHE="\${NEOAG_BASIC_DEPS_DIR}/refs/vep"
export NEOAG_VEP_CACHE_VERSION="105"
export NEOAG_VEP_PLUGINS="\${NEOAG_BASIC_DEPS_DIR}/work/vep_plugins"
export NEOAG_DBSNP_VCF="\${NEOAG_BASIC_DEPS_DIR}/refs/facets/reference/common_snp.hg38.vcf.gz"
export NEOAG_CTAT_LIB_DIR="\${NEOAG_BASIC_DEPS_DIR}/refs/ctat/current"
export CTAT_GENOME_LIB="\${NEOAG_CTAT_LIB_DIR}/ctat_genome_lib_build_dir"
if [[ ! -d "\${CTAT_GENOME_LIB}" && -d "\${NEOAG_CTAT_LIB_DIR}" ]]; then
  export CTAT_GENOME_LIB="\${NEOAG_CTAT_LIB_DIR}"
fi
export NXF_HOME="\${NEOAG_BASIC_DEPS_DIR}/work/nextflow_cache"
export NEOAG_EASYFUSE_REF="\${NEOAG_BASIC_DEPS_DIR}/refs/easyfuse/current"
export EASYFUSE_REF="\${NEOAG_EASYFUSE_REF}"
export SPECHLA_DB="\${NEOAG_BASIC_DEPS_DIR}/refs/hla/spechla"
export HLA_LA_GRAPH="\${NEOAG_BASIC_DEPS_DIR}/refs/hla/PRG_MHC_GRCh38_withIMGT"
export HLALA_GRAPH="\${HLA_LA_GRAPH}"
export OPTITYPE_REFERENCE="\${NEOAG_BASIC_DEPS_DIR}/refs/hla/optitype_reference"
export POLYSOLVER_HOME="\${NEOAG_BASIC_DEPS_DIR}/refs/lohhla/polysolver"
export NOVOALIGN_LICENSE_FILE="\${NEOAG_BASIC_DEPS_DIR}/refs/lohhla/novoalign.lic"
export PURPLE_REF_DIR="\${NEOAG_BASIC_DEPS_DIR}/refs/hmf/purple_reference"
export SEQUENZA_REF_FASTA="\${NEOAG_BASIC_DEPS_DIR}/refs/sequenza/reference/GRCh38.primary_assembly.chr.fa"
export SEQUENZA_GC_WIGGLE="\${NEOAG_BASIC_DEPS_DIR}/refs/sequenza/reference/Homo_sapiens.GRCh38.dna.primary_assembly.chr.gc50.wig.gz"
if [[ ! -s "\${SEQUENZA_GC_WIGGLE}" && -s "\${NEOAG_BASIC_DEPS_DIR}/refs/sequenza/reference/GRCh38.gc50.wig.gz" ]]; then
  export SEQUENZA_GC_WIGGLE="\${NEOAG_BASIC_DEPS_DIR}/refs/sequenza/reference/GRCh38.gc50.wig.gz"
fi
export SEQUENZA_FIT_R="\${NEOAG_BASIC_DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R"
if [[ ! -f "\${SEQUENZA_FIT_R}" ]]; then
  export SEQUENZA_FIT_R="\${NEOAG_BASIC_DEPS_DIR}/tools/sequenza/run_sequenza_fit.R"
fi
export BAM2SEQZ_WRAP="\${NEOAG_BASIC_DEPS_DIR}/tools/sequenza/bam2seqz_nulsafe.py"
if [[ -x "\${NEOAG_CONDA_BASE}/envs/neoag-samtools19/bin/samtools" ]]; then
  export SEQUENZA_SAMTOOLS="\${NEOAG_CONDA_BASE}/envs/neoag-samtools19/bin/samtools"
elif [[ -x "\${NEOAG_CONDA_BASE}/envs/neoag-sequenza/bin/samtools" ]]; then
  export SEQUENZA_SAMTOOLS="\${NEOAG_CONDA_BASE}/envs/neoag-sequenza/bin/samtools"
fi
export SEQUENZA_BIN="\${NEOAG_CONDA_BASE}/envs/neoag-sequenza/bin"
export ASCAT_REFERENCE_DIR="\${NEOAG_BASIC_DEPS_DIR}/refs/ascat/reference/WGS_hg38"
export SALMON_INDEX="\${NEOAG_BASIC_DEPS_DIR}/refs/rna/gencode_v49/salmon_index"
export SALMON_TX2GENE="\${NEOAG_BASIC_DEPS_DIR}/refs/rna/gencode_v49/tx2gene.tsv"

# Predictors / licenses
export NETMHCPAN_HOME="\${NEOAG_BASIC_DEPS_DIR}/licenses/predictors/netMHCpan"
export NEOAG_NETMHCPAN_BIN="\${NETMHCPAN_HOME}/netMHCpan"
export PRIME_HOME="\${NEOAG_BASIC_DEPS_DIR}/licenses/predictors/prime"
export MIXMHCPRED_HOME="\${NEOAG_BASIC_DEPS_DIR}/licenses/predictors/mixMHCpred_install"
export BIGMHC_DIR="\${NEOAG_BASIC_DEPS_DIR}/licenses/predictors/bigmhc"

# MHCflurry: prefer deps hint / user download dir (layout may need 2.0.0 -> 4/2.0.0 shim)
if [[ -f "\${NEOAG_BASIC_DEPS_DIR}/configs/mhcflurry_data_dir.txt" ]]; then
  export MHCFLURRY_DATA_DIR="\$(head -1 "\${NEOAG_BASIC_DEPS_DIR}/configs/mhcflurry_data_dir.txt" | tr -d '[:space:]')"
elif [[ -d "\${HOME}/.local/share/mhcflurry" ]]; then
  export MHCFLURRY_DATA_DIR="\${HOME}/.local/share/mhcflurry"
fi

# VEP: isolate Perl from system/miniconda (do not mix /root/miniconda3 PERL5LIB)
neoag_use_vep_perl() {
  local vep="\${NEOAG_CONDA_BASE}/envs/neoag-vep"
  if [[ ! -d "\$vep" ]]; then
    echo "[site.env] neoag-vep missing under \${NEOAG_CONDA_BASE}/envs" >&2
    return 1
  fi
  export NEOAG_VEP_BIN="\${vep}/bin/vep"
  export PATH="\${vep}/bin:\${PATH}"
  local pl=""
  local d
  for d in \\
    "\${vep}/lib/perl5/site_perl" \\
    "\${vep}/lib/perl5/vendor_perl" \\
    "\${vep}/lib/perl5/core_perl" \\
    "\${vep}/lib/perl5/5.32/site_perl" \\
    "\${vep}/lib/perl5/5.32/vendor_perl" \\
    "\${vep}/lib/perl5/5.32/core_perl"
  do
    [[ -d "\$d" ]] || continue
    if [[ -z "\$pl" ]]; then pl="\$d"; else pl="\$pl:\$d"; fi
  done
  if [[ -d "\${vep}/share" ]]; then
    local share_mod
    share_mod="\$(find "\${vep}/share" -maxdepth 3 -type d -name modules 2>/dev/null | head -1 || true)"
    if [[ -n "\$share_mod" ]]; then
      if [[ -z "\$pl" ]]; then pl="\$share_mod"; else pl="\$pl:\$share_mod"; fi
    fi
  fi
  export PERL5LIB="\$pl"
  export NEOAG_VEP_PERL5LIB="\$pl"
}

# Tool trees
export NEOAG_EASYFUSE_HOME="\${NEOAG_BASIC_DEPS_DIR}/tools/EasyFuse"
export NEOAG_STAR_FUSION_HOME="\${NEOAG_BASIC_DEPS_DIR}/tools/STAR-Fusion"
export HLALA_CONDA_BIN="\${NEOAG_BASIC_DEPS_DIR}/tools/neodata_tools/HLA-LA/.conda/bin"
export HLALA_HOME="\${NEOAG_BASIC_DEPS_DIR}/tools/neodata_tools/HLA-LA/.conda/opt/hla-la"
export SPECHLA_HOME="\${NEOAG_BASIC_DEPS_DIR}/tools/neodata_tools/SpecHLA"

# EasyFuse: recorded at install + re-detected every source (Ubuntu 22.04 only)
export NEOAG_EASYFUSE_SUPPORTED_AT_INSTALL="${ef_supported}"
export NEOAG_EASYFUSE_SKIP_REASON_AT_INSTALL="${ef_reason}"
_neoag_ef_ok=0
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "\${ID:-}" == "ubuntu" && "\${VERSION_ID:-}" == "22.04" ]]; then
    _neoag_ef_ok=1
  fi
fi
if [[ "\${_neoag_ef_ok}" -eq 1 ]]; then
  export NEOAG_EASYFUSE_SUPPORTED=1
  export NEOAG_EASYFUSE_SKIP_REASON=""
  export NEOAG_SKIP_EASYFUSE=0
else
  export NEOAG_EASYFUSE_SUPPORTED=0
  export NEOAG_EASYFUSE_SKIP_REASON="EasyFuse 仅支持 Ubuntu 22.04；当前主机不满足，请改用 STAR-Fusion 或在 22.04 机器上运行 EasyFuse"
  export NEOAG_SKIP_EASYFUSE=1
fi
unset _neoag_ef_ok

# Caches
export CONDA_PKGS_DIRS="\${NEOAG_BASIC_DEPS_DIR}/packages/conda_pkgs"
export PIP_CACHE_DIR="\${NEOAG_BASIC_DEPS_DIR}/packages/pip_cache"

echo "[site.env] NEOAG_BASIC_DEPS_DIR=\${NEOAG_BASIC_DEPS_DIR}"
echo "[site.env] NEOAG_ROOT=\${NEOAG_ROOT}"
echo "[site.env] NEOAG_CONDA_BASE=\${NEOAG_CONDA_BASE}"
echo "[site.env] EasyFuse supported=\${NEOAG_EASYFUSE_SUPPORTED}"
EOF
  chmod a+rwx "$out" 2>/dev/null || chmod a+rw "$out" || true
  ok "已写入可移植环境文件: $out"
}
