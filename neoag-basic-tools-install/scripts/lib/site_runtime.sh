#!/usr/bin/env bash
# Portable runtime overlay for 134 / 66 / 169.
# Sourced by configs/site.env.sh. Refs stay under DEPS_DIR; conda/tools may
# live on the host (OSS FUSE is a poor conda prefix).
#
# Gold lessons from sunbinbin:
#   - pVAC: prefer neoag-pvactools711; never TF_USE_LEGACY_KERAS=1
#   - never put neoag-tools / neoag-vep105 fake bcftools 0.1.19 on PATH
#   - WGS FASTA must be chr* (DEPS hg38 assembly38 is Ensembl "1,2,3…")
#   - EasyFuse only on Ubuntu 22.04
#   - production needs a full neo repo, not $DEPS_DIR/src/neo

: "${NEOAG_BASIC_DEPS_DIR:=/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"

# This-host only. Never /mnt/zjl-bgi-zzb. Never probe another machine's prefix.
neoag_this_host_id() {
  local ips hn
  ips=" $(hostname -I 2>/dev/null || true) "
  hn="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  if [[ "${ips}" == *" 10.200.65.66 "* || "${hn}" == *65.66* ]]; then
    printf '%s\n' 66
    return 0
  fi
  if [[ "${ips}" == *" 10.200.50.134 "* ]]; then
    printf '%s\n' 134
    return 0
  fi
  if [[ "${ips}" == *" 10.200.65.169 "* ]]; then
    printf '%s\n' 169
    return 0
  fi
  printf '%s\n' unknown
}

neoag_local_conda_prefix() {
  case "$(neoag_this_host_id)" in
    66) printf '%s\n' /root/neo/envs/miniforge3 ;;
    134) printf '%s\n' /home/na/miniforge3 ;;
    169) printf '%s\n' /root/neo/env_tool/miniforge3 ;;
  esac
}

neoag_local_neo_roots() {
  case "$(neoag_this_host_id)" in
    66|169)
      printf '%s\n' /root/neo/src/na0707_upload_release
      ;;
    134)
      printf '%s\n' /home/na/project/neoantigen/neoag_event_pipeline_na0707_sync_20260811
      printf '%s\n' /home/na/project/neoantigen/neoag_event_pipeline_v03_rc
      ;;
  esac
}

neoag_local_tools_roots() {
  case "$(neoag_this_host_id)" in
    66)
      printf '%s\n' /root/neo/envs/tools /root/neo/envs
      ;;
    134)
      printf '%s\n' /home/na/project/neoantigen/neoag_event_pipeline_v03_rc/tools
      ;;
    169)
      printf '%s\n' /root/neo/env_tool/tools /root/neo/env_tool
      ;;
  esac
}

_neoag_first_chr_contig() {
  local fa="$1"
  local fai="${fa}.fai"
  [[ -s "$fai" ]] || fai="$(readlink -f "$fa" 2>/dev/null).fai"
  [[ -s "$fai" ]] || return 1
  head -n 1 "$fai" | cut -f1
}

_neoag_is_fake_bcftools() {
  local b="$1"
  [[ -x "$b" ]] || return 1
  # pysam stub / ancient 0.1.19 prints empty or "bcftools 0.1.19"
  local v
  v="$("$b" --version 2>/dev/null | head -1 || true)"
  [[ -z "$v" || "$v" == *0.1.19* ]]
}

neoag_resolve_conda_base() {
  local c
  for c in \
    "${NEOAG_CONDA_BASE:-}" \
    "$(neoag_local_conda_prefix)"
  do
    [[ -n "$c" && -x "${c}/bin/conda" ]] || continue
    export NEOAG_CONDA_BASE="$c"
    export CONDA_EXE="${c}/bin/conda"
    return 0
  done
  echo "[site.env] ERROR: 本机未找到 conda（host=$(neoag_this_host_id)）。不要用别机前缀或 zjl 盘。" >&2
  return 1
}

neoag_resolve_neo_root() {
  local c
  local pick=""
  local full=""
  local roots=()
  [[ -n "${NEOAG_ROOT:-}" ]] && roots+=("${NEOAG_ROOT}")
  while IFS= read -r c; do
    [[ -n "$c" ]] && roots+=("$c")
  done < <(neoag_local_neo_roots)
  roots+=("${NEOAG_BASIC_DEPS_DIR}/src/neo")
  for c in "${roots[@]}"; do
    [[ -n "$c" && -d "$c" ]] || continue
    [[ -z "$pick" ]] && pick="$c"
    if [[ -d "${c}/src/neoag" || -f "${c}/pyproject.toml" ]] && [[ -f "${c}/conf/tools.env.sh" || -d "${c}/src/neoag" ]]; then
      full="$c"
      break
    fi
  done
  export NEOAG_ROOT="${full:-${pick}}"
  if [[ -d "${NEOAG_ROOT}/src" ]]; then
    export PYTHONPATH="${NEOAG_ROOT}/src${PYTHONPATH:+:${PYTHONPATH}}"
  fi
}

neoag_resolve_tools_root() {
  local c inner
  local roots=()
  [[ -n "${NEOAG_TOOLS_ROOT:-}" ]] && roots+=("${NEOAG_TOOLS_ROOT}")
  roots+=("${NEOAG_BASIC_DEPS_DIR}/tools")
  while IFS= read -r c; do
    [[ -n "$c" ]] && roots+=("$c")
  done < <(neoag_local_tools_roots)
  for c in "${roots[@]}"; do
    [[ -n "$c" && -d "$c" ]] || continue
    inner="$c"
    if [[ ! -d "${c}/STAR-Fusion" && -d "${c}/tools/STAR-Fusion" ]]; then
      inner="${c}/tools"
    fi
    if [[ -d "${inner}/STAR-Fusion" || -d "${inner}/EasyFuse" || -d "${inner}/HLA-LA" || -d "${inner}/neodata_tools" ]]; then
      export NEOAG_TOOLS_ROOT="$inner"
      return 0
    fi
  done
  export NEOAG_TOOLS_ROOT="${NEOAG_BASIC_DEPS_DIR}/tools"
}

neoag_resolve_chr_fasta() {
  local deps="${NEOAG_BASIC_DEPS_DIR}"
  local assembly="${deps}/refs/hg38/Homo_sapiens_assembly38.fasta"
  local seqz="${deps}/refs/sequenza/reference/GRCh38.primary_assembly.chr.fa"
  local pick="" contig

  export SEQUENZA_REF_FASTA="${SEQUENZA_REF_FASTA:-${seqz}}"

  for pick in "${NEOAG_REFERENCE_FASTA:-}" "${REF_FASTA:-}" "$seqz" "$assembly"; do
    [[ -n "$pick" && -s "$pick" ]] || continue
    contig="$(_neoag_first_chr_contig "$pick" || true)"
    if [[ "${contig}" == chr* ]]; then
      export NEOAG_REFERENCE_FASTA="$pick"
      export REF_FASTA="$pick"
      return 0
    fi
  done

  if [[ -s "$assembly" ]]; then
    export NEOAG_REFERENCE_FASTA="$assembly"
    export REF_FASTA="$assembly"
    echo "[site.env] WARN: 未找到 chr* FASTA，沿用 ${assembly}（首 contig=$( _neoag_first_chr_contig "$assembly" || echo '?' )）。WGS/Sequenza 请设 REF_FASTA=${seqz}" >&2
  fi
}

neoag_resolve_pvac_env() {
  local base="${NEOAG_CONDA_BASE:-}"
  local env=""
  local c
  for c in \
    "${NEOAG_PVAC_ENV:-}" \
    "${base}/envs/neoag-pvactools711" \
    "${base}/envs/neoag-tools"
  do
    [[ -n "$c" && -x "${c}/bin/pvacseq" ]] || continue
    env="$c"
    break
  done
  export NEOAG_PVAC_ENV="${env}"
  if [[ -n "$env" ]]; then
    export PVACSEQ_BIN="${env}/bin/pvacseq"
    export PVACFUSE_BIN="${env}/bin/pvacfuse"
    export PVACSPLICE_BIN="${env}/bin/pvacsplice"
  fi
  # 134 gold: 711 + no legacy keras. Setting this breaks MHCflurry in 711.
  unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true
}

neoag_pick_bin() {
  local name="$1"
  shift
  local c
  for c in "$@"; do
    [[ -n "$c" && -x "$c" ]] || continue
    echo "$c"
    return 0
  done
  return 1
}

neoag_resolve_bins() {
  local base="${NEOAG_CONDA_BASE:-}"
  local e="${base}/envs"
  local tools="${NEOAG_TOOLS_ROOT:-}"
  local deps="${NEOAG_BASIC_DEPS_DIR}"

  local star
  star="$(neoag_pick_bin STAR \
    "${STAR_BIN:-}" \
    "${NEOAG_STAR_BIN:-}" \
    "${e}/neoag-fusion/bin/STAR" \
    "${e}/neoag-splicemutr/bin/STAR" \
    "${e}/neoag-longrna/bin/STAR" || true)"
  [[ -n "$star" ]] && export STAR_BIN="$star" NEOAG_STAR_BIN="$star"

  local smt
  smt="$(neoag_pick_bin samtools \
    "${SAMTOOLS_BIN:-}" \
    "${e}/neoag-fusion/bin/samtools" \
    "${e}/neoag-sequenza/bin/samtools" \
    "${e}/neoag-tools/bin/samtools" || true)"
  [[ -n "$smt" ]] && export SAMTOOLS_BIN="$smt"

  local bcf=""
  local cand
  for cand in \
    "${BCFTOOLS:-}" \
    "${e}/neoag-fusion/bin/bcftools" \
    "${e}/neoag-gatk/bin/bcftools" \
    "${e}/neoag-tools/bin/bcftools"
  do
    [[ -n "$cand" && -x "$cand" ]] || continue
    if _neoag_is_fake_bcftools "$cand"; then
      continue
    fi
    bcf="$cand"
    break
  done
  [[ -n "$bcf" ]] && export BCFTOOLS="$bcf" BCFTOOLS_BIN="$bcf"

  local vep
  vep="$(neoag_pick_bin vep \
    "${VEP_BIN:-}" \
    "${e}/neoag-vep105/bin/vep" \
    "${e}/neoag-vep/bin/vep" \
    "${NEOAG_ROOT:-}/bin/vep-neoag" || true)"
  [[ -n "$vep" ]] && export VEP_BIN="$vep" NEOAG_VEP_BIN="$vep"

  local salmon
  salmon="$(neoag_pick_bin salmon \
    "${SALMON_BIN:-}" \
    "${e}/neoag-salmon-cpp/bin/salmon" \
    "${e}/neoag-fusion/bin/salmon" \
    "${e}/neoag-tools/bin/salmon" || true)"
  [[ -n "$salmon" ]] && export SALMON_BIN="$salmon" NEOAG_SALMON_BIN="$salmon"

  local reg
  reg="$(neoag_pick_bin regtools \
    "${NEOAG_REGTOOLS_BIN:-}" \
    "${e}/neoag-splice/bin/regtools" \
    "${e}/neoag-fusion/bin/regtools" || true)"
  [[ -n "$reg" ]] && export NEOAG_REGTOOLS_BIN="$reg"

  export NEOAG_STAR_FUSION_HOME="${NEOAG_STAR_FUSION_HOME:-}"
  if [[ -z "${NEOAG_STAR_FUSION_HOME}" || ! -d "${NEOAG_STAR_FUSION_HOME}" ]]; then
    for cand in \
      "${deps}/tools/STAR-Fusion" \
      "${tools}/STAR-Fusion" \
      "${NEOAG_ROOT:-}/tools/STAR-Fusion"
    do
      [[ -d "$cand" ]] && export NEOAG_STAR_FUSION_HOME="$cand" && break
    done
  fi

  export NEOAG_EASYFUSE_HOME="${NEOAG_EASYFUSE_HOME:-}"
  if [[ -z "${NEOAG_EASYFUSE_HOME}" || ! -d "${NEOAG_EASYFUSE_HOME}" ]]; then
    for cand in \
      "${deps}/tools/EasyFuse" \
      "${tools}/EasyFuse"
    do
      [[ -d "$cand" ]] && export NEOAG_EASYFUSE_HOME="$cand" && break
    done
  fi

  if [[ -x "${e}/neoag-samtools19/bin/samtools" ]]; then
    export SEQUENZA_SAMTOOLS="${e}/neoag-samtools19/bin/samtools"
  elif [[ -x "${e}/neoag-sequenza/bin/samtools" ]]; then
    export SEQUENZA_SAMTOOLS="${e}/neoag-sequenza/bin/samtools"
  fi
  export SEQUENZA_BIN="${e}/neoag-sequenza/bin"
}

neoag_sanitize_path() {
  local new="" p bcf
  local IFS=':'
  # shellcheck disable=SC2086
  set -- ${PATH}
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    bcf="${p}/bcftools"
    if [[ -x "$bcf" ]] && _neoag_is_fake_bcftools "$bcf"; then
      continue
    fi
    if [[ -z "$new" ]]; then new="$p"; else new="${new}:${p}"; fi
  done
  export PATH="$new"
}

neoag_use_vep_perl() {
  local vep="${NEOAG_CONDA_BASE}/envs/neoag-vep"
  if [[ -x "${NEOAG_CONDA_BASE}/envs/neoag-vep105/bin/vep" ]]; then
    vep="${NEOAG_CONDA_BASE}/envs/neoag-vep105"
  fi
  if [[ ! -d "$vep" ]]; then
    echo "[site.env] neoag-vep missing under ${NEOAG_CONDA_BASE}/envs" >&2
    return 1
  fi
  export NEOAG_VEP_BIN="${vep}/bin/vep"
  export VEP_BIN="${NEOAG_VEP_BIN}"
  export PATH="${vep}/bin:${PATH}"
  local pl="" d
  for d in \
    "${vep}/lib/perl5/site_perl" \
    "${vep}/lib/perl5/vendor_perl" \
    "${vep}/lib/perl5/core_perl" \
    "${vep}/lib/perl5/5.32/site_perl" \
    "${vep}/lib/perl5/5.32/vendor_perl" \
    "${vep}/lib/perl5/5.32/core_perl"
  do
    [[ -d "$d" ]] || continue
    if [[ -z "$pl" ]]; then pl="$d"; else pl="${pl}:$d"; fi
  done
  if [[ -d "${vep}/share" ]]; then
    local share_mod
    share_mod="$(find "${vep}/share" -maxdepth 3 -type d -name modules 2>/dev/null | head -1 || true)"
    if [[ -n "$share_mod" ]]; then
      if [[ -z "$pl" ]]; then pl="$share_mod"; else pl="${pl}:${share_mod}"; fi
    fi
  fi
  export PERL5LIB="$pl"
  export NEOAG_VEP_PERL5LIB="$pl"
  neoag_sanitize_path
}

neoag_set_easyfuse_os() {
  local ok=0
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22.04" ]]; then
      ok=1
    fi
  fi
  if [[ "$ok" -eq 1 ]]; then
    export NEOAG_EASYFUSE_SUPPORTED=1
    export NEOAG_EASYFUSE_SKIP_REASON=""
    export NEOAG_SKIP_EASYFUSE=0
  else
    export NEOAG_EASYFUSE_SUPPORTED=0
    export NEOAG_EASYFUSE_SKIP_REASON="EasyFuse 仅支持 Ubuntu 22.04；当前主机不满足，请改用 STAR-Fusion 或在 22.04 机器上运行 EasyFuse"
    export NEOAG_SKIP_EASYFUSE=1
  fi
}

# SpecHLA: code+db live on shared deps; spechla_env must be a local conda prefix
# (FUSE neoag_100T is a bad place for conda envs). Prefer host unpack / gold tree.
neoag_resolve_spechla() {
  local deps="${1:-${NEOAG_BASIC_DEPS_DIR}}"
  local home cand
  home="${deps}/tools/neodata_tools/SpecHLA"
  if [[ ! -d "${home}" && -d "${NEOAG_TOOLS_ROOT:-}/SpecHLA" ]]; then
    home="${NEOAG_TOOLS_ROOT}/SpecHLA"
  fi
  # Portable deps may ship only source/; expose script/bin/db the runners expect.
  if [[ -d "${home}/source/script" && ! -e "${home}/script" ]]; then
    ln -sfn source/script "${home}/script" 2>/dev/null || true
  fi
  if [[ -d "${home}/source/bin" && ! -e "${home}/bin" ]]; then
    ln -sfn source/bin "${home}/bin" 2>/dev/null || true
  fi
  if [[ ! -e "${home}/db" ]]; then
    if [[ -d "${deps}/refs/hla/spechla/db" ]]; then
      ln -sfn "${deps}/refs/hla/spechla/db" "${home}/db" 2>/dev/null || true
    elif [[ -d "${deps}/refs/hla/spechla" && -f "${deps}/refs/hla/spechla/HLA_FREQ_HLA_I_II.dat" ]]; then
      ln -sfn "${deps}/refs/hla/spechla" "${home}/db" 2>/dev/null || true
    fi
  fi
  export SPECHLA_HOME="${home}"
  export SPECHLA_DB="${SPECHLA_DB:-${deps}/refs/hla/spechla}"
  for cand in \
    "${SPECHLA_ENV:-}" \
    "${NEOAG_CONDA_BASE:-}/envs/spechla_env" \
    "${NEOAG_TOOLS_ROOT:-}/SpecHLA/spechla_env" \
    "${home}/spechla_env"
  do
    [[ -n "${cand}" && -d "${cand}/bin" ]] || continue
    export SPECHLA_ENV="${cand}"
    break
  done
}

# Pick the first predictor tree that contains a sentinel file.
# Prefers install-deps complete copies over incomplete liup trees
# (sunbinbin 20260814 BigMHC was models/ only — no src/predict.py).
neoag_pick_pred_dir() {
  local sentinel="$1"
  local cand
  shift
  for cand in "$@"; do
    [[ -n "${cand}" && -e "${cand}${sentinel}" ]] || continue
    printf '%s' "${cand}"
    return 0
  done
  return 1
}

neoag_export_production_predictors() {
  local pred="$1"
  local fallback="${2:-}"
  local picked

  picked="$(neoag_pick_pred_dir "/src/predict.py" "${pred}/bigmhc" "${fallback}/bigmhc" || true)"
  export BIGMHC_DIR="${picked:-${pred}/bigmhc}"

  picked="$(neoag_pick_pred_dir "/deepimmuno-cnn.py" "${pred}/DeepImmuno" "${fallback}/DeepImmuno" || true)"
  export DEEPIMMUNO_DIR="${picked:-${pred}/DeepImmuno}"

  picked="$(neoag_pick_pred_dir "/PRIME" "${pred}/prime" "${fallback}/prime" || true)"
  export PRIME_HOME="${picked:-${pred}/prime}"

  picked="$(neoag_pick_pred_dir "/MixMHCpred" "${pred}/mixMHCpred_install" "${fallback}/mixMHCpred_install" || true)"
  export MIXMHCPRED_HOME="${picked:-${pred}/mixMHCpred_install}"

  picked="$(neoag_pick_pred_dir "/Linux_x86_64/bin/netChop" \
    "${pred}/netchop/netchop-3.1" "${fallback}/netchop/netchop-3.1" || true)"
  export NETCHOP_HOME="${picked:-${pred}/netchop/netchop-3.1}"
  export NEOAG_NETCHOP_BIN="${NETCHOP_HOME}/Linux_x86_64/bin/netChop"
  export NETCHOP_BIN="${NEOAG_NETCHOP_BIN}"
  export NETCHOP="${NETCHOP_HOME}/Linux_x86_64"

  picked="$(neoag_pick_pred_dir "/Linux_x86_64/bin/netMHCstabpan" \
    "${pred}/netMHCstabpan" || true)"
  export NETMHCSTABPAN_HOME="${picked:-${pred}/netMHCstabpan}"
  export NETMHCSTABPAN_BIN="${NETMHCSTABPAN_HOME}/netMHCstabpan"

  export NEOAG_PRIME_BIN="${PRIME_HOME}/PRIME"
  export MIXMHCPRED_BIN="${MIXMHCPRED_HOME}/MixMHCpred"
  if [[ -n "${NEOAG_CONDA_BASE:-}" ]]; then
    export BIGMHC_PYTHON="${BIGMHC_PYTHON:-${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python}"
    export NEOAG_PRIME_PYTHON="${NEOAG_PRIME_PYTHON:-${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python}"
  fi
}

neoag_site_activate() {
  local deps="${NEOAG_BASIC_DEPS_DIR}"
  export NEODATA_ROOT="${deps}"
  export NEOAG_SHARED_REF_DIR="${deps}/refs"
  export NEOAG_VEP_CACHE="${deps}/refs/vep"
  export VEP_CACHE="${NEOAG_VEP_CACHE}"
  export NEOAG_VEP_CACHE_VERSION="105"
  export NEOAG_VEP_PLUGINS="${deps}/work/vep_plugins"
  export NEOAG_DBSNP_VCF="${deps}/refs/facets/reference/common_snp.hg38.vcf.gz"
  export NEOAG_CTAT_LIB_DIR="${deps}/refs/ctat/current"
  export CTAT_GENOME_LIB="${NEOAG_CTAT_LIB_DIR}/ctat_genome_lib_build_dir"
  if [[ ! -d "${CTAT_GENOME_LIB}" && -d "${NEOAG_CTAT_LIB_DIR}" ]]; then
    export CTAT_GENOME_LIB="${NEOAG_CTAT_LIB_DIR}"
  fi
  if [[ -d "${CTAT_GENOME_LIB}" ]]; then
    export STAR_INDEX="${STAR_INDEX:-${CTAT_GENOME_LIB}/ref_genome.fa.star.idx}"
    export RNA_REF_FASTA="${RNA_REF_FASTA:-${CTAT_GENOME_LIB}/ref_genome.fa}"
    export RNA_GTF="${RNA_GTF:-${CTAT_GENOME_LIB}/ref_annot.gtf}"
    export PVACSPLICE_REF_FASTA="${PVACSPLICE_REF_FASTA:-${RNA_REF_FASTA}}"
  fi
  export NXF_HOME="${deps}/work/nextflow_cache"
  export NEOAG_EASYFUSE_REF="${deps}/refs/easyfuse/current"
  export EASYFUSE_REF="${NEOAG_EASYFUSE_REF}"
  export FUSIONCATCHER_DATA="${FUSIONCATCHER_DATA:-${NEOAG_EASYFUSE_REF}/fusioncatcher_index}"
  export SPECHLA_DB="${deps}/refs/hla/spechla"
  export HLA_LA_GRAPH="${deps}/refs/hla/PRG_MHC_GRCh38_withIMGT"
  export HLALA_GRAPH="${HLA_LA_GRAPH}"
  export OPTITYPE_REFERENCE="${deps}/refs/hla/optitype_reference"
  export POLYSOLVER_HOME="${deps}/refs/lohhla/polysolver"
  export NOVOALIGN_LICENSE_FILE="${deps}/refs/lohhla/novoalign.lic"
  # LOHHLA R scripts + hla.dat (copied into deps; do not hardcode 134 /home/na)
  if [[ -f "${deps}/tools/lohhla/LOHHLAscript.R" ]]; then
    export LOHHLA_HOME="${LOHHLA_HOME:-${deps}/tools/lohhla}"
  elif [[ -f "${deps}/tools/neodata_tools/LOHHLA/LOHHLAscript.R" ]]; then
    export LOHHLA_HOME="${LOHHLA_HOME:-${deps}/tools/neodata_tools/LOHHLA}"
  fi
  # FACETS helper (runFACETS.R) + snp-pileup from deps FACETS conda tree
  if [[ -f "${deps}/tools/facets/runFACETS.R" ]]; then
    export FACETS_HOME="${FACETS_HOME:-${deps}/tools/facets}"
  fi
  local snp_pileup=""
  for snp_pileup in \
    "${SNP_PILEUP_BIN:-}" \
    "${deps}/tools/neodata_tools/FACETS/.conda/bin/snp-pileup" \
    "${NEOAG_CONDA_BASE:-}/envs/neoag-facets/bin/snp-pileup"
  do
    [[ -n "${snp_pileup}" && -x "${snp_pileup}" ]] || continue
    export SNP_PILEUP_BIN="${snp_pileup}"
    break
  done
  # HMF tools reference bundle (AMBER/COBALT/PURPLE)
  if [[ -d "${deps}/refs/hmf/purple_reference/amber" ]]; then
    export HMFTOOLS_REF_ROOT="${HMFTOOLS_REF_ROOT:-${deps}/refs/hmf/purple_reference}"
    export PURPLE_REF_DIR="${PURPLE_REF_DIR:-${deps}/refs/hmf/purple_reference}"
  fi
  # pVACtools / VEP convenience aliases used by case wrappers
  if [[ -n "${NEOAG_PVAC_ENV:-}" ]]; then
    export PVAC_ENV="${PVAC_ENV:-${NEOAG_PVAC_ENV}}"
  fi
  if [[ -n "${VEP_BIN:-}" ]]; then
    export NEOAG_VEP_BIN="${NEOAG_VEP_BIN:-${VEP_BIN}}"
  fi
  if [[ -d "${NEOAG_VEP_PLUGINS:-}" ]]; then
    :
  elif [[ -f "${NEOAG_PVAC_ENV:-}/lib/python3.11/site-packages/pvactools/tools/pvacseq/VEP_plugins/Wildtype.pm" ]]; then
    export NEOAG_VEP_PLUGINS="${NEOAG_PVAC_ENV}/lib/python3.11/site-packages/pvactools/tools/pvacseq/VEP_plugins"
  fi
  if [[ -x "${NEOAG_CONDA_BASE:-}/envs/neoag-tools/bin/bcftools" ]]; then
    export BCFTOOLS="${BCFTOOLS:-${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/bcftools}"
  fi
  export SEQUENZA_GC_WIGGLE="${SEQUENZA_GC_WIGGLE:-${deps}/refs/sequenza/reference/Homo_sapiens.GRCh38.dna.primary_assembly.chr.gc50.wig.gz}"
  if [[ ! -s "${SEQUENZA_GC_WIGGLE}" && -s "${deps}/refs/sequenza/reference/GRCh38.gc50.wig.gz" ]]; then
    export SEQUENZA_GC_WIGGLE="${deps}/refs/sequenza/reference/GRCh38.gc50.wig.gz"
  fi
  export SEQUENZA_FIT_R="${deps}/tools/sequenza/run_sequenza_fit.R"
  if [[ ! -f "${SEQUENZA_FIT_R}" ]]; then
    export SEQUENZA_FIT_R="${deps}/src/neo/scripts/run_sequenza_fit.R"
  fi
  export BAM2SEQZ_WRAP="${deps}/tools/sequenza/bam2seqz_nulsafe.py"
  export ASCAT_REFERENCE_DIR="${deps}/refs/ascat/reference/WGS_hg38"
  export SALMON_INDEX="${SALMON_INDEX:-${deps}/refs/rna/gencode_v49/salmon_index}"
  export SALMON_TX2GENE="${SALMON_TX2GENE:-${deps}/refs/rna/gencode_v49/tx2gene.tsv}"
  export RSEM_TRANSCRIPTS_FA="${RSEM_TRANSCRIPTS_FA:-${deps}/refs/rna/gencode.v49.transcripts.fa.gz}"
  export NEOAG_SNAF_DB="${NEOAG_SNAF_DB:-${deps}/refs/snaf/reference/data}"
  export SNAF_DB="${SNAF_DB:-${NEOAG_SNAF_DB}}"
  if [[ -d "${deps}/tools/SpliceMutr" ]]; then
    export SPLICEMUTR_HOME="${SPLICEMUTR_HOME:-${deps}/tools/SpliceMutr}"
  fi
  export GTF="${GTF:-${RNA_GTF:-${CTAT_GENOME_LIB:-}/ref_annot.gtf}}"

  export NETMHCPAN_HOME="${deps}/licenses/predictors/netMHCpan"
  export NEOAG_NETMHCPAN_BIN="${NETMHCPAN_HOME}/netMHCpan"
  export NEOAG_TOOL_QUARANTINE="${NEOAG_TOOL_QUARANTINE:-${deps}/licenses/predictors}"
  export NETMHCSTABPAN_HOME="${deps}/licenses/predictors/netMHCstabpan"
  export NETMHCSTABPAN_BIN="${NETMHCSTABPAN_HOME}/netMHCstabpan"

  if [[ -f "${deps}/configs/mhcflurry_data_dir.txt" ]]; then
    export MHCFLURRY_DATA_DIR="$(head -1 "${deps}/configs/mhcflurry_data_dir.txt" | tr -d '[:space:]')"
  elif [[ -d "${HOME}/.local/share/mhcflurry" ]]; then
    export MHCFLURRY_DATA_DIR="${HOME}/.local/share/mhcflurry"
  fi

  neoag_resolve_conda_base || true
  neoag_export_production_predictors "${deps}/licenses/predictors" ""
  export NETMHCSTABPAN_HOME="${deps}/licenses/predictors/netMHCstabpan"
  export NETMHCSTABPAN_BIN="${NETMHCSTABPAN_HOME}/netMHCstabpan"
  neoag_resolve_neo_root
  neoag_resolve_tools_root
  neoag_resolve_chr_fasta
  neoag_resolve_pvac_env
  neoag_resolve_bins
  neoag_set_easyfuse_os

  export HLALA_CONDA_BIN="${deps}/tools/neodata_tools/HLA-LA/.conda/bin"
  export HLALA_HOME="${deps}/tools/neodata_tools/HLA-LA/.conda/opt/hla-la"
  if [[ ! -d "${HLALA_HOME}" && -d "${NEOAG_TOOLS_ROOT}/HLA-LA" ]]; then
    export HLALA_HOME="${NEOAG_TOOLS_ROOT}/HLA-LA"
    export HLALA_CONDA_BIN="${NEOAG_TOOLS_ROOT}/HLA-LA/.conda/bin"
  fi
  neoag_resolve_spechla "${deps}"

  export CONDA_PKGS_DIRS="${deps}/packages/conda_pkgs"
  export PIP_CACHE_DIR="${deps}/packages/pip_cache"
  export NEOAG_FORCE_CPU="${NEOAG_FORCE_CPU:-1}"
  export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-}"
  export PVAC_ALGORITHMS="${PVAC_ALGORITHMS:-MHCflurry MHCflurryEL}"

  local prepend=""
  [[ -x "${NEOAG_CONDA_BASE:-}/bin/conda" ]] && prepend="${NEOAG_CONDA_BASE}/bin"
  [[ -d "${deps}/tools/neodata_tools/bin" ]] && prepend="${prepend:+${prepend}:}${deps}/tools/neodata_tools/bin"
  [[ -n "${PRIME_HOME:-}" && -d "${PRIME_HOME}" ]] && prepend="${prepend:+${prepend}:}${PRIME_HOME}"
  [[ -n "${MIXMHCPRED_HOME:-}" && -d "${MIXMHCPRED_HOME}" ]] && prepend="${prepend:+${prepend}:}${MIXMHCPRED_HOME}"
  [[ -n "${NETMHCSTABPAN_HOME:-}" && -d "${NETMHCSTABPAN_HOME}" ]] && prepend="${prepend:+${prepend}:}${NETMHCSTABPAN_HOME}"
  [[ -n "${BCFTOOLS:-}" ]] && prepend="${prepend:+${prepend}:}$(dirname "${BCFTOOLS}")"
  [[ -n "${SAMTOOLS_BIN:-}" ]] && prepend="${prepend:+${prepend}:}$(dirname "${SAMTOOLS_BIN}")"
  if [[ -n "$prepend" ]]; then
    export PATH="${prepend}:${PATH:-}"
  fi
  neoag_sanitize_path

  if [[ "${NEOAG_SITE_QUIET:-0}" != "1" ]]; then
    echo "[site.env] NEOAG_BASIC_DEPS_DIR=${NEOAG_BASIC_DEPS_DIR}"
    echo "[site.env] NEOAG_ROOT=${NEOAG_ROOT:-}"
    echo "[site.env] NEOAG_CONDA_BASE=${NEOAG_CONDA_BASE:-}"
    echo "[site.env] NEOAG_PVAC_ENV=${NEOAG_PVAC_ENV:-}"
    echo "[site.env] REF_FASTA=${REF_FASTA:-}"
    echo "[site.env] EasyFuse supported=${NEOAG_EASYFUSE_SUPPORTED:-}"
  fi
}
