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
export PATH="${ROOT}/bin:${PATH}"

PATIENT_ID="${PATIENT_ID:?ERROR: set PATIENT_ID}"
TUMOR_SAMPLE="${TUMOR_SAMPLE_ID:-${PATIENT_ID}_tumor}"
NORMAL_SAMPLE="${NORMAL_SAMPLE_ID:-${PATIENT_ID}_blood}"
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

mkdir -p "${AMBER_DIR}" "${COBALT_DIR}" "${PURPLE_DIR}" "$(dirname "${LOG}")"
exec > >(tee -a "${LOG}") 2>&1

echo "==> purple_steps $(date -Is) step=${PURPLE_STEP}"
echo "    tumor=${TUMOR_SAMPLE} bam=${TUMOR_BAM}"
echo "    normal=${NORMAL_SAMPLE} bam=${NORMAL_BAM}"
echo "    somatic_vcf=${SOMATIC_VCF:-<none>}"
echo "    jvm=${HMFTOOLS_JVM_MEM} threads=${THREADS}"
echo "    out=${OUT}"

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
