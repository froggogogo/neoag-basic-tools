#!/usr/bin/env bash
# Cross-host neoantigen pipeline environment audit (66 / 134 / 169).
# Emits TSV lines: host\tcategory\titem\tstatus\tdetail
# Usage: bash audit_host_pipeline_env.sh
set -uo pipefail

DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
if [[ -f "${DEPS}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  NEOAG_SITE_QUIET=1 source "${DEPS}/configs/site.env.sh" 2>/dev/null || true
fi

HOST_ID="$(hostname -s 2>/dev/null || hostname)"
IP_HINT=""
case "$(hostname -I 2>/dev/null | awk '{print $1}')" in
  10.200.65.66) HOST_ID=66 ;;
  10.200.50.134) HOST_ID=134 ;;
  10.200.65.169) HOST_ID=169 ;;
esac
BASE="${NEOAG_CONDA_BASE:-}"
E="${BASE:+${BASE}/envs}"
SS="${DEPS}/shared_scripts"

emit() {
  # category item status detail
  printf '%s\t%s\t%s\t%s\t%s\n' "$HOST_ID" "$1" "$2" "$3" "${4:-}"
}

ok() { emit "$1" "$2" "OK" "$3"; }
miss() { emit "$1" "$2" "MISSING" "$3"; }
fail() { emit "$1" "$2" "FAIL" "$3"; }
warn() { emit "$1" "$2" "WARN" "$3"; }
skip() { emit "$1" "$2" "SKIP" "$3"; }

printf 'host\tcategory\titem\tstatus\tdetail\n'

# --- host / conda ---
os="unknown"
ef=0
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  os="${PRETTY_NAME:-unknown}"
  [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == "22.04" ]] && ef=1
fi
emit "meta" "hostname" "INFO" "$(hostname)"
emit "meta" "os" "INFO" "$os"
emit "meta" "conda_base" "$([[ -n "$BASE" && -x "${BASE}/bin/conda" ]] && echo OK || echo MISSING)" "${BASE:-unset}"
emit "meta" "neoag_root" "$([[ -n "${NEOAG_ROOT:-}" && -d "${NEOAG_ROOT}" ]] && echo OK || echo MISSING)" "${NEOAG_ROOT:-unset}"
emit "meta" "deps_dir" "$([[ -d "$DEPS" ]] && echo OK || echo MISSING)" "$DEPS"
emit "meta" "easyfuse_os" "INFO" "ubuntu22=$ef"

# Required host-local conda envs (pipeline tools)
REQ_ENVS=(
  neoag-tools
  neoag-fusion
  neoag-splice
  neoag-splicemutr
  neoag-sequenza
  neoag-samtools19
  neoag-vep
  neoag-gatk
  neoag-ascat
  neoag-facets
  neoag-optitype
  neoag-snaf
  neoag-pvactools711
  neoag-salmon-cpp
  spechla_env
)

if [[ -z "$E" ]]; then
  for name in "${REQ_ENVS[@]}"; do
    miss "conda_env" "$name" "no NEOAG_CONDA_BASE"
  done
else
  for name in "${REQ_ENVS[@]}"; do
    if [[ -d "${E}/${name}" ]]; then
      ok "conda_env" "$name" "${E}/${name}"
    else
      miss "conda_env" "$name" "${E}/${name}"
    fi
  done
  # optional but used
  for name in neoag-polysolver lohhla-mod neoag-longrna; do
    if [[ -d "${E}/${name}" ]]; then
      ok "conda_env_opt" "$name" "${E}/${name}"
    else
      emit "conda_env_opt" "$name" "ABSENT" "${E}/${name}"
    fi
  done
fi

check_bin() {
  local cat="$1" item="$2" path="$3"
  if [[ -n "$path" && -x "$path" ]]; then
    ok "$cat" "$item" "$path"
  else
    miss "$cat" "$item" "${path:-unset}"
  fi
}

check_dir() {
  local cat="$1" item="$2" path="$3"
  if [[ -n "$path" && -d "$path" ]] && [[ -n "$(ls -A "$path" 2>/dev/null || true)" ]]; then
    ok "$cat" "$item" "$path"
  else
    miss "$cat" "$item" "${path:-unset}"
  fi
}

check_file() {
  local cat="$1" item="$2" path="$3"
  if [[ -n "$path" && -e "$path" ]]; then
    ok "$cat" "$item" "$path"
  else
    miss "$cat" "$item" "${path:-unset}"
  fi
}

# --- key binaries ---
check_bin "bin" "STAR" "${STAR_BIN:-${E:+${E}/neoag-fusion/bin/STAR}}"
check_bin "bin" "salmon" "${SALMON_BIN:-${E:+${E}/neoag-salmon-cpp/bin/salmon}}"
check_bin "bin" "regtools" "${NEOAG_REGTOOLS_BIN:-${E:+${E}/neoag-splice/bin/regtools}}"
check_bin "bin" "sequenza-utils" "${E:+${E}/neoag-sequenza/bin/sequenza-utils}"
check_bin "bin" "samtools19" "${SEQUENZA_SAMTOOLS:-${E:+${E}/neoag-samtools19/bin/samtools}}"
check_bin "bin" "vep" "${VEP_BIN:-${E:+${E}/neoag-vep/bin/vep}}"
check_bin "bin" "pvacseq" "${PVACSEQ_BIN:-${E:+${E}/neoag-pvactools711/bin/pvacseq}}"
check_bin "bin" "snp-pileup" "${E:+${E}/neoag-facets/bin/snp-pileup}"

# samtools19 version
if [[ -x "${E}/neoag-samtools19/bin/samtools" ]]; then
  ver="$("${E}/neoag-samtools19/bin/samtools" --version 2>/dev/null | head -1 || true)"
  if echo "$ver" | grep -q '1\.9'; then
    ok "bin" "samtools19_ver" "$ver"
  else
    fail "bin" "samtools19_ver" "$ver"
  fi
fi

# --- LOHHLA: uses neoag-fusion R (run_lohhla_sample.sh) ---
LOHHLA_R="${E:+${E}/neoag-fusion/bin/Rscript}"
if [[ -x "$LOHHLA_R" ]]; then
  ok "lohhla" "Rscript_neoag-fusion" "$LOHHLA_R"
  for pkg in optparse sequential HLAprofiler HLAminer; do
    :
  done
  # core packages LOHHLA actually needs
  for pkg in optparse data.table GenomicRanges Rsamtools Biostrings; do
    if "$LOHHLA_R" -e "cat(requireNamespace('${pkg}', quietly=TRUE))" 2>/dev/null | grep -q TRUE; then
      ok "lohhla_rpkg" "$pkg" "neoag-fusion"
    else
      miss "lohhla_rpkg" "$pkg" "neoag-fusion missing ${pkg}"
    fi
  done
else
  miss "lohhla" "Rscript_neoag-fusion" "${LOHHLA_R:-unset}"
fi

# Also check lohhla-mod if present (66-only leftover)
if [[ -x "${E}/lohhla-mod/bin/Rscript" ]]; then
  if "${E}/lohhla-mod/bin/Rscript" -e 'cat(requireNamespace("optparse", quietly=TRUE))' 2>/dev/null | grep -q TRUE; then
    ok "lohhla_rpkg" "optparse@lohhla-mod" "present"
  else
    warn "lohhla_rpkg" "optparse@lohhla-mod" "env exists but no optparse (not used by gold path)"
  fi
fi

# LOHHLA assets
check_file "lohhla_asset" "LOHHLAscript.R" "${LOHHLA_HOME:-${DEPS}/tools/lohhla}/LOHHLAscript.R"
check_dir "lohhla_asset" "polysolver_data" "${POLYSOLVER_HOME:-${DEPS}/refs/lohhla/polysolver}/data/complete"
check_file "lohhla_asset" "novoalign.lic" "${NOVOALIGN_LICENSE_FILE:-${DEPS}/refs/lohhla/novoalign.lic}"
check_file "lohhla_asset" "picard.jar" "$(
  ls "${E}/neoag-gatk/share/picard-"*/picard.jar 2>/dev/null | head -1
)"

# --- SNAF python packages ---
SNAF_PY="${E:+${E}/neoag-snaf/bin/python}"
if [[ -x "$SNAF_PY" ]]; then
  ok "snaf" "python" "$SNAF_PY"
  # import smoke
  for mod in snaf pandas mhcflurry mhcgnomes biothings_client mygene; do
    if "$SNAF_PY" -c "import ${mod}" 2>/dev/null; then
      ok "snaf_pkg" "$mod" "import_ok"
    else
      miss "snaf_pkg" "$mod" "import_fail"
    fi
  done
  # Class2Pair specifically (known 66 failure mode)
  if "$SNAF_PY" -c "from mhcgnomes import Class2Pair" 2>/dev/null; then
    ok "snaf_pkg" "mhcgnomes.Class2Pair" "import_ok"
  else
    fail "snaf_pkg" "mhcgnomes.Class2Pair" "cannot import Class2Pair"
  fi
  # version pins
  detail="$("$SNAF_PY" - <<'PY' 2>/dev/null || true
import importlib
for n in ("snaf","mhcgnomes","mhcflurry","biothings_client","mygene"):
    try:
        m=importlib.import_module(n)
        print(f"{n}={getattr(m,'__version__',getattr(m,'VERSION','?'))}")
    except Exception as e:
        print(f"{n}=ERR:{type(e).__name__}")
PY
)"
  emit "snaf" "versions" "INFO" "${detail//$'\n'/; }"
else
  miss "snaf" "python" "${SNAF_PY:-unset}"
fi
check_dir "snaf_asset" "refs_snaf" "${DEPS}/refs/snaf"

# docker altanalyze (optional soft)
if command -v docker >/dev/null 2>&1; then
  if docker image inspect neoag-altanalyze:snaf >/dev/null 2>&1; then
    ok "snaf" "docker_altanalyze" "neoag-altanalyze:snaf"
  else
    warn "snaf" "docker_altanalyze" "image missing (pipeline may fallback to counts.original.full)"
  fi
else
  warn "snaf" "docker" "docker not installed"
fi

# --- Sequenza R ---
SEQ_R="${E:+${E}/neoag-sequenza/bin/Rscript}"
if [[ -x "$SEQ_R" ]]; then
  for pkg in sequenza data.table; do
    if "$SEQ_R" -e "cat(requireNamespace('${pkg}', quietly=TRUE))" 2>/dev/null | grep -q TRUE; then
      ok "sequenza_rpkg" "$pkg" "neoag-sequenza"
    else
      miss "sequenza_rpkg" "$pkg" "neoag-sequenza"
    fi
  done
fi

# --- SpliceMutr ---
SM_R="${E:+${E}/neoag-splicemutr/bin/Rscript}"
if [[ -x "$SM_R" ]]; then
  if "$SM_R" -e 'suppressPackageStartupMessages(library(BSgenome.Hsapiens.UCSC.hg38)); cat("OK")' >/dev/null 2>&1; then
    ok "splicemutr_rpkg" "BSgenome.Hsapiens.UCSC.hg38" "neoag-splicemutr"
  else
    miss "splicemutr_rpkg" "BSgenome.Hsapiens.UCSC.hg38" "neoag-splicemutr"
  fi
fi
check_dir "splicemutr_asset" "R_library_splicemutr" "${DEPS}/shared_refs/R_library_splicemutr"

# --- ASCAT ---
AS_R="${E:+${E}/neoag-ascat/bin/Rscript}"
if [[ -x "$AS_R" ]]; then
  if "$AS_R" -e 'suppressPackageStartupMessages(library(ASCAT)); cat("OK")' >/dev/null 2>&1; then
    ok "ascat_rpkg" "ASCAT" "neoag-ascat"
  else
    miss "ascat_rpkg" "ASCAT" "neoag-ascat"
  fi
fi

# --- HMFTOOLS / PURPLE ---
HMF_BIN="${DEPS}/tools/neodata_tools/HMFTOOLS/.conda/bin"
for b in amber cobalt purple; do
  check_bin "hmftools" "$b" "${HMF_BIN}/${b}"
done
check_dir "hmftools_ref" "purple_reference" "${DEPS}/refs/hmf/purple_reference"
check_file "hmftools_ref" "amber_loci" "${DEPS}/refs/hmf/purple_reference/amber/GermlineHetPon.38.vcf.gz"
check_file "hmftools_ref" "gc_profile" "${DEPS}/refs/hmf/purple_reference/cobalt/GC_profile.1000bp.38.cnp"

# --- HLA tools ---
check_dir "hla" "HLA-LA" "${HLALA_HOME:-${DEPS}/tools/neodata_tools/HLA-LA}"
check_dir "hla" "SpecHLA" "${SPECHLA_HOME:-}"
check_bin "hla" "OptiType" "${E:+${E}/neoag-optitype/bin/OptiTypePipeline.py}"

# --- shared scripts (100T templates) ---
for rel in \
  case_templates/run_lohhla.sh \
  case_templates/run_purple_steps.sh \
  case_templates/run_cnv_hla_parallel.sh \
  sequenza/run_sequenza_steps.sh \
  snaf/run_snaf_pipeline.sh \
  snaf/snaf_sample_workflow.py \
  splicemutr/run_splicemutr_patient.sh \
  short_rna_templates/run_short_rna_all.sh
do
  check_file "shared_script" "$rel" "${SS}/${rel}"
done
check_file "tool_script" "run_sequenza_fit.R" "${DEPS}/tools/sequenza/run_sequenza_fit.R"
check_file "tool_script" "bam2seqz_nulsafe.py" "${DEPS}/tools/sequenza/bam2seqz_nulsafe.py"

# --- shared refs ---
check_file "ref" "chr_fasta" "${REF_FASTA:-${DEPS}/refs/sequenza/reference/GRCh38.primary_assembly.chr.fa}"
check_dir "ref" "vep_cache" "${NEOAG_VEP_CACHE:-${DEPS}/refs/vep}"
check_dir "ref" "rsem_gencode_v49" "${DEPS}/shared_refs/rsem_gencode_v49"
check_dir "ref" "ctat" "${CTAT_GENOME_LIB:-}"

# --- predictors ---
check_file "pred" "bigmhc_predict.py" "${BIGMHC_DIR:-}/src/predict.py"
check_file "pred" "deepimmuno" "${DEEPIMMUNO_DIR:-}/deepimmuno-cnn.py"
check_file "pred" "mixmhcpred" "${MIXMHCPRED_BIN:-${MIXMHCPRED_HOME:-}/MixMHCpred}"
check_file "pred" "prime" "${NEOAG_PRIME_BIN:-${PRIME_HOME:-}/PRIME}"
check_file "pred" "netchop" "${NEOAG_NETCHOP_BIN:-}"
check_file "pred" "netmhcstabpan" "${NETMHCSTABPAN_BIN:-${DEPS}/licenses/predictors/netMHCstabpan/netMHCstabpan}"

# MHCflurry models (host home — can differ)
mf="${MHCFLURRY_DATA_DIR:-${HOME}/.local/share/mhcflurry}"
if [[ -e "${mf}/2.0.0/models_class1_presentation" || -e "${mf}/4/2.0.0/models_class1_presentation" ]]; then
  ok "mhcflurry" "models" "$mf"
else
  # also check snaf env user home path under root
  miss "mhcflurry" "models" "$mf"
fi

# --- NEOAG_ROOT run_lohhla_sample ---
check_file "neo_script" "run_lohhla_sample.sh" "${NEOAG_ROOT:-}/scripts/run_lohhla_sample.sh"

emit "meta" "audit_done" "INFO" "$(date -Is)"
