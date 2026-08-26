#!/usr/bin/env bash
# PURPLE suite steps: amber | cobalt | purple | pileup(amber+cobalt) | fit(purple) | all
# Resume-safe via .amber.done / .cobalt.done / .fit.done markers.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_SCRIPT_DIR}/lib_portable_env.sh"
# shellcheck source=/dev/null
source "${_SCRIPT_DIR}/lib_site_defaults.sh"
resolve_ref_fasta
ROOT="${NEOAG_ROOT}"
DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
# Prefer neoag-100T HMFTOOLS; never rely on missing NEOAG_ROOT/tools/HMFTOOLS/.conda (66).
HMFTOOLS_BIN=""
for _hmf in \
  "${DEPS}/tools/neodata_tools/HMFTOOLS/.conda/bin" \
  "${HMFTOOLS_CONDA_BIN:-}" \
  "${ROOT}/tools/HMFTOOLS/.conda/bin"
do
  [[ -n "${_hmf}" && -x "${_hmf}/amber" && -x "${_hmf}/cobalt" && -x "${_hmf}/purple" ]] || continue
  HMFTOOLS_BIN="${_hmf}"
  break
done
if [[ -z "${HMFTOOLS_BIN}" ]]; then
  echo "ERROR: HMFTOOLS amber/cobalt/purple not found under:" >&2
  echo "  ${DEPS}/tools/neodata_tools/HMFTOOLS/.conda/bin" >&2
  echo "  ${ROOT}/tools/HMFTOOLS/.conda/bin" >&2
  echo "Install/rsync HMFTOOLS .conda onto neoag-100T deps (not NEOAG_ROOT alone)." >&2
  exit 2
fi
export PATH="${HMFTOOLS_BIN}:${PATH}"
# Avoid conda/mamba trying a missing NEOAG_ROOT HMFTOOLS prefix
if [[ -n "${CONDA_PREFIX:-}" && "${CONDA_PREFIX}" == *"/HMFTOOLS/.conda" && ! -d "${CONDA_PREFIX}" ]]; then
  unset CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_PROMPT_MODIFIER || true
fi

PATIENT_ID="${PATIENT_ID:?ERROR: set PATIENT_ID}"
TUMOR_BAM="${TUMOR_BAM:?ERROR: set TUMOR_BAM}"
NORMAL_BAM="${NORMAL_BAM:?ERROR: set NORMAL_BAM}"
SOMATIC_VCF="${SOMATIC_VCF:-}"
OUT="${OUTDIR:?ERROR: set OUTDIR}"
AMBER_DIR="${OUT}/amber"
COBALT_DIR="${OUT}/cobalt"
PURPLE_DIR="${OUT}/purple"
LOG="${LOG:-${OUT}/run.log}"
THREADS="${THREADS:-8}"
PURPLE_STEP="${PURPLE_STEP:-all}"
FORCE="${FORCE:-0}"
HMFTOOLS_JVM_MEM="${HMFTOOLS_JVM_MEM:--Xmx32g}"
RUN_PURPLE_DRIVERS="${RUN_PURPLE_DRIVERS:-0}"

HMFTOOLS_REF_ROOT="${HMFTOOLS_REF_ROOT:-${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/refs/hmf/purple_reference}"
HMFTOOLS_AMBER_LOCI="${HMFTOOLS_AMBER_LOCI:-${HMFTOOLS_REF_ROOT}/amber/GermlineHetPon.38.vcf.gz}"
HMFTOOLS_GC_PROFILE="${HMFTOOLS_GC_PROFILE:-${HMFTOOLS_REF_ROOT}/cobalt/GC_profile.1000bp.38.cnp}"
HMFTOOLS_ENSEMBL_DATA_DIR="${HMFTOOLS_ENSEMBL_DATA_DIR:-${HMFTOOLS_REF_ROOT}/ensembl_data_cache_38}"
HMFTOOLS_DRIVER_GENE_PANEL="${HMFTOOLS_DRIVER_GENE_PANEL:-${HMFTOOLS_REF_ROOT}/purple/DriverGenePanel.38.tsv}"
HMFTOOLS_SOMATIC_HOTSPOTS="${HMFTOOLS_SOMATIC_HOTSPOTS:-${HMFTOOLS_REF_ROOT}/purple/KnownHotspots.somatic.38.vcf.gz}"

DONE_AMBER="${AMBER_DIR}/.amber.done"
DONE_COBALT="${COBALT_DIR}/.cobalt.done"
DONE_FIT="${PURPLE_DIR}/.fit.done"

# --- Sample ID resolution (PURPLE -tumor/-reference must match VCF genotype columns) ---
#
# VCF *file* path: ONLY from case.config / env SOMATIC_VCF (user-supplied).
# Never discover or guess the VCF by filename (e.g. *tumor*.vcf). One case = one somatic VCF.
#
# What we resolve here: which *column name inside that VCF* is tumor vs normal, so that
# purple -tumor / -reference match AMBER/COBALT sample IDs and VCF genotypes.
#
# Priority:
#   1) explicit TUMOR_SAMPLE_ID / NORMAL_SAMPLE_ID
#   2) BAM stem ↔ VCF sample column (primary; covers FP*_L0*_451 lane IDs)
#   3) optional keyword fallback: patient + tumor|blood|normal (separator-agnostic)
#   4) ${PATIENT_ID}_tumor / ${PATIENT_ID}_blood
_norm_token() {
  # lowercase + keep only alnum so jinganxin_tumor / jinganxin-tumor / jinganxin.tumor align
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

_bam_stem() {
  local b
  b="$(basename "$1")"
  b="${b%.bam}"
  b="${b%.cram}"
  b="${b%.align}"
  printf '%s' "$b"
}

_vcf_samples() {
  # Read genotype sample names from the SOMATIC_VCF path already set by the caller.
  # Under `set -o pipefail`, gzip|awk early-exit yields SIGPIPE (141) and empties
  # the sample list → wrong PATIENT_ID_tumor fallback. Parse inside a subshell
  # with pipefail off so the header read always succeeds.
  local vcf="$1"
  local line=""
  line="$(
    set +e +o pipefail
    if [[ "$vcf" == *.gz ]]; then
      gzip -dc "$vcf" 2>/dev/null | awk '/^#CHROM/{print; exit}'
    else
      awk '/^#CHROM/{print; exit}' "$vcf"
    fi
  )"
  [[ -n "$line" ]] || return 0
  # fields 10+ are sample names
  awk -F'\t' '{for (i=10; i<=NF; i++) print $i}' <<<"$line"
}

_pick_vcf_sample_by_bam() {
  # usage: _pick_vcf_sample_by_bam <bam> <sample1> <sample2> ...
  local bam="$1"
  shift
  local samples=("$@")
  [[ ${#samples[@]} -gt 0 ]] || return 1
  local stem stem_n bam_n s sn
  stem="$(_bam_stem "$bam")"
  stem_n="$(_norm_token "$stem")"
  bam_n="$(_norm_token "$(basename "$bam")")"
  for s in "${samples[@]}"; do
    sn="$(_norm_token "$s")"
    if [[ -n "$stem_n" && ( "$sn" == *"$stem_n"* || "$stem_n" == *"$sn"* ) ]]; then
      printf '%s' "$s"
      return 0
    fi
    if [[ -n "$bam_n" && "$bam_n" == *"$sn"* ]]; then
      printf '%s' "$s"
      return 0
    fi
  done
  return 1
}

_pick_vcf_sample_by_keyword() {
  # Optional fallback only: patient ID + role token in the VCF column name.
  # usage: _pick_vcf_sample_by_keyword <role:tumor|normal> <sample1> ...
  local role="$1"
  shift
  local samples=("$@")
  [[ ${#samples[@]} -gt 0 ]] || return 1
  local patient_n role_keys=() s sn key
  patient_n="$(_norm_token "${PATIENT_ID}")"
  case "$role" in
    tumor) role_keys=(tumor tumour) ;;
    normal) role_keys=(blood normal germline) ;;
    *) return 1 ;;
  esac
  for s in "${samples[@]}"; do
    sn="$(_norm_token "$s")"
    [[ "$sn" == *"${patient_n}"* ]] || continue
    for key in "${role_keys[@]}"; do
      if [[ "$sn" == *"$key"* ]]; then
        printf '%s' "$s"
        return 0
      fi
    done
  done
  return 1
}

_pick_vcf_sample() {
  # usage: _pick_vcf_sample <role:tumor|normal> <bam> <sample1> <sample2> ...
  local role="$1"
  local bam="$2"
  shift 2
  local samples=("$@")
  local picked
  # 1) BAM stem (primary)
  if picked="$(_pick_vcf_sample_by_bam "${bam}" "${samples[@]}")"; then
    printf '%s' "$picked"
    return 0
  fi
  # 2) keyword fallback (optional)
  if picked="$(_pick_vcf_sample_by_keyword "${role}" "${samples[@]}")"; then
    printf '%s' "$picked"
    return 0
  fi
  return 1
}

resolve_purple_sample_ids() {
  local tumor_override="${TUMOR_SAMPLE_ID:-}"
  local normal_override="${NORMAL_SAMPLE_ID:-}"
  local tumor_fallback="${PATIENT_ID}_tumor"
  local normal_fallback="${PATIENT_ID}_blood"
  local -a samples=()
  local picked how

  # SOMATIC_VCF must already be set from case.config / env — we only parse columns inside it.
  if [[ -n "${SOMATIC_VCF}" && -f "${SOMATIC_VCF}" ]]; then
    mapfile -t samples < <(_vcf_samples "${SOMATIC_VCF}")
  fi

  if [[ -n "${tumor_override}" ]]; then
    TUMOR_SAMPLE="${tumor_override}"
    how="override"
  elif [[ ${#samples[@]} -gt 0 ]] && picked="$(_pick_vcf_sample tumor "${TUMOR_BAM}" "${samples[@]}")"; then
    TUMOR_SAMPLE="${picked}"
    how="bam-stem-or-keyword"
  else
    TUMOR_SAMPLE="${tumor_fallback}"
    how="fallback"
  fi
  echo "==> resolved TUMOR_SAMPLE=${TUMOR_SAMPLE} (${how}; VCF path from case.config SOMATIC_VCF, not filename guess)"

  if [[ -n "${normal_override}" ]]; then
    NORMAL_SAMPLE="${normal_override}"
    how="override"
  elif [[ ${#samples[@]} -gt 0 ]] && picked="$(_pick_vcf_sample normal "${NORMAL_BAM}" "${samples[@]}")"; then
    NORMAL_SAMPLE="${picked}"
    how="bam-stem-or-keyword"
  else
    NORMAL_SAMPLE="${normal_fallback}"
    how="fallback"
  fi
  echo "==> resolved NORMAL_SAMPLE=${NORMAL_SAMPLE} (${how})"

  # If AMBER already finished under a different sample name, force pileup redo for consistency with VCF.
  if [[ -f "${DONE_AMBER}" && "${FORCE}" != "1" ]]; then
    if ! compgen -G "${AMBER_DIR}/${NORMAL_SAMPLE}.amber*" >/dev/null 2>&1 \
      && ! compgen -G "${AMBER_DIR}/${TUMOR_SAMPLE}.amber*" >/dev/null 2>&1; then
      echo "==> WARN: AMBER done markers exist but outputs do not match resolved samples (${TUMOR_SAMPLE}/${NORMAL_SAMPLE}); clearing AMBER/COBALT done for re-pileup"
      rm -f "${DONE_AMBER}" "${DONE_COBALT}" "${DONE_FIT}"
    fi
  fi
}

mkdir -p "${AMBER_DIR}" "${COBALT_DIR}" "${PURPLE_DIR}" "$(dirname "${LOG}")"
exec > >(tee -a "${LOG}") 2>&1

resolve_purple_sample_ids

echo "==> purple_steps $(date -Is) step=${PURPLE_STEP}"
echo "    tumor=${TUMOR_SAMPLE} bam=${TUMOR_BAM}"
echo "    normal=${NORMAL_SAMPLE} bam=${NORMAL_BAM}"
echo "    somatic_vcf=${SOMATIC_VCF:-<none>}"
echo "    jvm=${HMFTOOLS_JVM_MEM} threads=${THREADS}"
echo "    out=${OUT}"
echo "    HMFTOOLS_BIN=${HMFTOOLS_BIN}"
echo "    amber=$(command -v amber)"

require_file() {
  [[ -f "$1" ]] || { echo "ERROR: missing $2: $1" >&2; exit 2; }
}

require_file "${TUMOR_BAM}" "tumor BAM"
require_file "${TUMOR_BAM}.bai" "tumor BAM index"
require_file "${NORMAL_BAM}" "normal BAM"
require_file "${NORMAL_BAM}.bai" "normal BAM index"
require_file "${REF_FASTA}" "reference FASTA"

run_amber() {
  if [[ -f "${DONE_AMBER}" && "${FORCE}" != "1" ]]; then
    echo "==> AMBER already done"
    return 0
  fi
  require_file "${HMFTOOLS_AMBER_LOCI}" "AMBER loci VCF"
  echo "==> AMBER start $(date -Is)"
  amber \
    "${HMFTOOLS_JVM_MEM}" \
    -reference "${NORMAL_SAMPLE}" \
    -reference_bam "${NORMAL_BAM}" \
    -tumor "${TUMOR_SAMPLE}" \
    -tumor_bam "${TUMOR_BAM}" \
    -loci "${HMFTOOLS_AMBER_LOCI}" \
    -ref_genome_version 38 \
    -ref_genome "${REF_FASTA}" \
    -threads "${THREADS}" \
    -output_dir "${AMBER_DIR}"
  date -Is > "${DONE_AMBER}"
  echo "==> AMBER done $(date -Is)"
}

run_cobalt() {
  if [[ -f "${DONE_COBALT}" && "${FORCE}" != "1" ]]; then
    echo "==> COBALT already done"
    return 0
  fi
  require_file "${HMFTOOLS_GC_PROFILE}" "COBALT GC profile"
  echo "==> COBALT start $(date -Is)"
  cobalt \
    "${HMFTOOLS_JVM_MEM}" \
    -reference "${NORMAL_SAMPLE}" \
    -reference_bam "${NORMAL_BAM}" \
    -tumor "${TUMOR_SAMPLE}" \
    -tumor_bam "${TUMOR_BAM}" \
    -gc_profile "${HMFTOOLS_GC_PROFILE}" \
    -ref_genome_version 38 \
    -ref_genome "${REF_FASTA}" \
    -threads "${THREADS}" \
    -output_dir "${COBALT_DIR}"
  date -Is > "${DONE_COBALT}"
  echo "==> COBALT done $(date -Is)"
}

run_purple() {
  if [[ -f "${DONE_FIT}" && "${FORCE}" != "1" ]]; then
    echo "==> PURPLE already done"
    return 0
  fi
  require_file "${HMFTOOLS_GC_PROFILE}" "COBALT GC profile"
  [[ -d "${HMFTOOLS_ENSEMBL_DATA_DIR}" ]] || { echo "ERROR: missing ensembl cache: ${HMFTOOLS_ENSEMBL_DATA_DIR}" >&2; exit 2; }
  [[ -f "${DONE_AMBER}" ]] || { echo "ERROR: AMBER not done; run PURPLE_STEP=amber first" >&2; exit 1; }
  [[ -f "${DONE_COBALT}" ]] || { echo "ERROR: COBALT not done; run PURPLE_STEP=cobalt first" >&2; exit 1; }

  local extra=()
  if [[ -n "${SOMATIC_VCF}" ]]; then
    require_file "${SOMATIC_VCF}" "somatic VCF"
    extra+=(-somatic_vcf "${SOMATIC_VCF}")
  fi
  if [[ "${RUN_PURPLE_DRIVERS}" == "1" ]]; then
    require_file "${HMFTOOLS_DRIVER_GENE_PANEL}" "driver gene panel"
    require_file "${HMFTOOLS_SOMATIC_HOTSPOTS}" "somatic hotspots"
    extra+=(
      -driver_gene_panel "${HMFTOOLS_DRIVER_GENE_PANEL}"
      -somatic_hotspots "${HMFTOOLS_SOMATIC_HOTSPOTS}"
    )
  fi

  rm -f "${DONE_FIT}"
  echo "==> PURPLE start $(date -Is)"
  purple \
    "${HMFTOOLS_JVM_MEM}" \
    -reference "${NORMAL_SAMPLE}" \
    -tumor "${TUMOR_SAMPLE}" \
    -amber_dir "${AMBER_DIR}" \
    -cobalt_dir "${COBALT_DIR}" \
    -ref_genome_version 38 \
    -ref_genome "${REF_FASTA}" \
    -gc_profile "${HMFTOOLS_GC_PROFILE}" \
    -ensembl_data_dir "${HMFTOOLS_ENSEMBL_DATA_DIR}" \
    "${extra[@]}" \
    -threads "${THREADS}" \
    -output_dir "${PURPLE_DIR}" \
    -ignore_plot_errors
  date -Is > "${DONE_FIT}"
  echo "==> PURPLE done $(date -Is)"
}

case "${PURPLE_STEP}" in
  amber) run_amber ;;
  cobalt) run_cobalt ;;
  pileup) run_amber; run_cobalt ;;
  purple|fit) run_purple ;;
  all) run_amber; run_cobalt; run_purple ;;
  *) echo "ERROR: PURPLE_STEP must be amber|cobalt|pileup|purple|fit|all" >&2; exit 2 ;;
esac

echo "==> purple_steps finished $(date -Is)"
