#!/usr/bin/env bash
# Portable Sequenza pileup + fit (sunbinbin 2026-08-17 gold path).
# pileup: per-chrom bam2seqz (NUL-safe) → merge raw chrom seqz → seqz_binning (may emit fake .gz)
# fit:    chrom-split fread Rscript (resolves fake .gz by magic bytes)
# Do NOT per-chrom bin then gzip -dc merge — binning output is often plain TSV named .gz.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DEPS_DIR="/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps"
DEPS_DIR="${DEPS_DIR:-${NEOAG_BASIC_DEPS_DIR:-${DEFAULT_DEPS_DIR}}}"

if [[ -f "${DEPS_DIR}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${DEPS_DIR}/configs/site.env.sh"
fi

: "${SAMPLE_ID:?ERROR: set SAMPLE_ID}"
: "${TUMOR_BAM:?ERROR: set TUMOR_BAM}"
: "${NORMAL_BAM:?ERROR: set NORMAL_BAM}"

OUTDIR="${OUTDIR:-${CASE_ROOT:+${CASE_ROOT}/sequenza}}"
OUTDIR="${OUTDIR:?ERROR: set OUTDIR or CASE_ROOT}"
NEOAG_CONDA_BASE="${NEOAG_CONDA_BASE:-${DEPS_DIR}/software/miniforge3}"
ENV="${SEQUENZA_ENV:-neoag-sequenza}"
SEQUENZA_BIN="${NEOAG_CONDA_BASE}/envs/${ENV}/bin"
SEQUENZA_PY="${SEQUENZA_PY:-${SEQUENZA_BIN}/python}"

REF="${REF_FASTA:-${SEQUENZA_REF_FASTA:-${NEOAG_REFERENCE_FASTA:-}}}"
GC="${GC_WIGGLE:-${SEQUENZA_GC_WIGGLE:-}}"
if [[ -z "$GC" ]]; then
  for g in \
    "${DEPS_DIR}/refs/sequenza/reference/Homo_sapiens.GRCh38.dna.primary_assembly.chr.gc50.wig.gz" \
    "${DEPS_DIR}/refs/sequenza/reference/GRCh38.gc50.wig.gz"
  do
    [[ -s "$g" ]] && GC="$g" && break
  done
fi

FIT_R="${SEQUENZA_FIT_R:-}"
if [[ -z "$FIT_R" ]]; then
  for r in \
    "${DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R" \
    "${DEPS_DIR}/tools/sequenza/run_sequenza_fit.R" \
    "${_SCRIPT_DIR}/run_sequenza_fit.R" \
    "${_SCRIPT_DIR}/../../patches/run_sequenza_fit.fread.R"
  do
    [[ -f "$r" ]] && FIT_R="$r" && break
  done
fi

BAM2SEQZ_WRAP="${BAM2SEQZ_WRAP:-}"
if [[ -z "$BAM2SEQZ_WRAP" ]]; then
  for w in \
    "${DEPS_DIR}/tools/sequenza/bam2seqz_nulsafe.py" \
    "${_SCRIPT_DIR}/bam2seqz_nulsafe.py"
  do
    [[ -f "$w" ]] && BAM2SEQZ_WRAP="$w" && break
  done
fi

resolve_samtools() {
  local c ver
  if [[ -n "${SAMTOOLS:-}" && -x "${SAMTOOLS}" ]]; then
    echo "${SAMTOOLS}"
    return 0
  fi
  for c in \
    "${SEQUENZA_SAMTOOLS:-}" \
    "${NEOAG_CONDA_BASE}/envs/neoag-samtools19/bin/samtools" \
    "${DEPS_DIR}/software/samtools-1.9/bin/samtools"
  do
    [[ -n "$c" && -x "$c" ]] || continue
    echo "$c"
    return 0
  done
  c="${SEQUENZA_BIN}/samtools"
  [[ -x "$c" ]] && echo "$c" && return 0
  return 1
}

SAMTOOLS="$(resolve_samtools)" || {
  echo "ERROR: samtools not found (want 1.9 for mpileup)" >&2
  exit 1
}
TABIX="${TABIX:-${SEQUENZA_BIN}/tabix}"
CHROMS="${CHROMS:-chr1 chr2 chr3 chr4 chr5 chr6 chr7 chr8 chr9 chr10 chr11 chr12 chr13 chr14 chr15 chr16 chr17 chr18 chr19 chr20 chr21 chr22 chrX chrY}"
CHUNK_JOBS="${CHUNK_JOBS:-2}"
BIN_WINDOW="${BIN_WINDOW:-50}"
QLIMIT="${QLIMIT:-20}"
MIN_DEPTH_N="${MIN_DEPTH_N:-20}"
HOM="${HOM:-0.9}"
HET="${HET:-0.25}"
SEQUENZA_STEP="${SEQUENZA_STEP:-all}"
FORCE="${FORCE:-0}"
LOG="${LOG:-${OUTDIR}/run.log}"
MERGED="${OUTDIR}/${SAMPLE_ID}.merged.seqz.gz"
BINNED="${OUTDIR}/${SAMPLE_ID}.small.seqz.gz"
DONE_PILEUP="${OUTDIR}/.pileup.done"
DONE_FIT="${OUTDIR}/.fit.done"

mkdir -p "${OUTDIR}/chrom" "${OUTDIR}/sequenza_fit" "${OUTDIR}/tmp" "$(dirname "${LOG}")"
export TMPDIR="${TMPDIR:-${OUTDIR}/tmp}"
export TMP="${TMP:-${TMPDIR}}"
export TEMP="${TEMP:-${TMPDIR}}"
exec > >(tee -a "${LOG}") 2>&1

echo "[$(date -Is)] sequenza step=${SEQUENZA_STEP} sample=${SAMPLE_ID}"
echo "    tumor=${TUMOR_BAM}"
echo "    normal=${NORMAL_BAM}"
echo "    ref=${REF}"
echo "    gc=${GC}"
echo "    fit_r=${FIT_R}"
echo "    outdir=${OUTDIR}"
echo "    samtools=${SAMTOOLS} ($("${SAMTOOLS}" --version 2>/dev/null | head -1 || echo '?'))"
echo "    wrap=${BAM2SEQZ_WRAP}"

st_ver="$("${SAMTOOLS}" --version 2>/dev/null | awk 'NR==1{print $2}')"
if [[ "${st_ver}" != 1.9* ]]; then
  echo "WARN: mpileup samtools=${st_ver} (want 1.9). 1.23+ may emit NULs; wrapper mitigates but 1.9 is preferred." >&2
fi

for f in "${TUMOR_BAM}" "${NORMAL_BAM}" "${REF}" "${GC}" "${BAM2SEQZ_WRAP}" "${FIT_R}"; do
  [[ -s "$f" || -f "$f" ]] || { echo "ERROR missing $f" >&2; exit 1; }
done
[[ -x "${SEQUENZA_PY}" ]] || { echo "ERROR missing ${SEQUENZA_PY} (neoag-sequenza)" >&2; exit 1; }
[[ -x "${SEQUENZA_BIN}/sequenza-utils" ]] || { echo "ERROR missing sequenza-utils in ${SEQUENZA_BIN}" >&2; exit 1; }
[[ -x "${TABIX}" ]] || { echo "ERROR missing tabix ${TABIX}" >&2; exit 1; }

if [[ "${CHROMS}" == *chr* ]]; then
  fai="${REF}.fai"
  [[ -s "${fai}" ]] || fai="$(readlink -f "${REF}" 2>/dev/null).fai"
  first_ctg="$(head -n 1 "${fai}" 2>/dev/null | cut -f1 || true)"
  if [[ -z "${first_ctg}" || "${first_ctg}" != chr* ]]; then
    echo "ERROR: REF contig style mismatch. CHROMS use chr* but REF.fai starts with '${first_ctg:-?}'" >&2
    echo "       Use GATK-style hg38 FASTA (chr1…). REF=${REF}" >&2
    exit 1
  fi
  echo "[$(date -Is)] REF contig check OK (first=${first_ctg})"
fi

run_env() {
  local cmd="$1"
  shift
  "${SEQUENZA_BIN}/${cmd}" "$@"
}

run_chrom() {
  local chrom="$1"
  local safe
  safe="$(echo "${chrom}" | tr ':/-' '___')"
  local seqz="${OUTDIR}/chrom/${SAMPLE_ID}.${safe}.seqz.gz"
  if [[ -s "${seqz}" && "${FORCE}" != "1" ]] && gzip -t "${seqz}" 2>/dev/null; then
    echo "[$(date -Is)] reuse ${chrom} -> ${seqz}"
    return 0
  fi
  echo "[$(date -Is)] bam2seqz ${chrom}"
  local tmp="${seqz}.tmp.gz"
  rm -f "${tmp}" "${seqz}"
  "${SEQUENZA_PY}" "${BAM2SEQZ_WRAP}" bam2seqz \
    -n "${NORMAL_BAM}" \
    -t "${TUMOR_BAM}" \
    -gc "${GC}" \
    -F "${REF}" \
    -S "${SAMTOOLS}" \
    -T "${TABIX}" \
    -q "${QLIMIT}" \
    -N "${MIN_DEPTH_N}" \
    --hom "${HOM}" \
    --het "${HET}" \
    -C "${chrom}" \
    -o "${tmp}"
  if [[ ! -s "${tmp}" ]] || ! gzip -t "${tmp}" 2>/dev/null; then
    echo "ERROR: bam2seqz produced invalid gzip for ${chrom}: ${tmp}" >&2
    rm -f "${tmp}"
    return 1
  fi
  mv "${tmp}" "${seqz}"
}

do_pileup() {
  if [[ -s "${BINNED}" && -f "${DONE_PILEUP}" && "${FORCE}" != "1" ]]; then
    echo "[$(date -Is)] sequenza pileup already done -> ${BINNED}"
    return 0
  fi
  export -f run_chrom
  export SAMPLE_ID TUMOR_BAM NORMAL_BAM REF GC OUTDIR SAMTOOLS TABIX QLIMIT MIN_DEPTH_N HOM HET FORCE
  export SEQUENZA_PY BAM2SEQZ_WRAP
  # shellcheck disable=SC2086
  printf "%s\n" ${CHROMS} | xargs -I{} -P "${CHUNK_JOBS}" bash -c "run_chrom \"{}\""

  echo "[$(date -Is)] validate chrom seqz"
  local chrom safe f last_nf
  for chrom in ${CHROMS}; do
    safe="$(echo "${chrom}" | tr ':/-' '___')"
    f="${OUTDIR}/chrom/${SAMPLE_ID}.${safe}.seqz.gz"
    if [[ ! -s "$f" ]] || ! gzip -t "$f" 2>/dev/null; then
      echo "ERROR missing/invalid chrom seqz $f" >&2
      exit 1
    fi
    # gzip -t can pass on truncated content; seqz rows must have 14 fields
    last_nf="$(zcat "$f" | tail -n 1 | awk -F'\t' '{print NF}')"
    if [[ "${last_nf}" != "14" ]]; then
      echo "ERROR truncated/bad last line NF=${last_nf} in $f (need 14); delete and re-run bam2seqz" >&2
      exit 1
    fi
  done

  echo "[$(date -Is)] merge chrom seqz"
  {
    first=1
    for chrom in ${CHROMS}; do
      safe="$(echo "${chrom}" | tr ':/-' '___')"
      f="${OUTDIR}/chrom/${SAMPLE_ID}.${safe}.seqz.gz"
      if [[ "$first" == 1 ]]; then
        zcat "$f"
        first=0
      else
        zcat "$f" | tail -n +2
      fi
      # Newline between chrom blocks avoids merged-line field unpack errors at binning.
      printf '\n'
    done
  } | gzip -c > "${MERGED}.tmp"
  gzip -t "${MERGED}.tmp"
  mv "${MERGED}.tmp" "${MERGED}"

  echo "[$(date -Is)] seqz_binning"
  run_env sequenza-utils seqz_binning -s "${MERGED}" -w "${BIN_WINDOW}" -T "${TABIX}" -o "${BINNED}.tmp"
  # Output is often plain TSV named .gz; do not gzip -t here — R fit resolves via magic bytes.
  mv "${BINNED}.tmp" "${BINNED}"
  date -Is > "${DONE_PILEUP}"
  echo "[$(date -Is)] sequenza pileup done"
}

do_fit() {
  [[ -s "${BINNED}" ]] || { echo "ERROR: missing ${BINNED}; run SEQUENZA_STEP=pileup first" >&2; exit 1; }
  if [[ -f "${DONE_FIT}" && -s "${OUTDIR}/sequenza_fit/${SAMPLE_ID}.sequenza_summary.tsv" && "${FORCE}" != "1" ]]; then
    echo "[$(date -Is)] sequenza fit already done"
    return 0
  fi
  rm -f "${DONE_FIT}"
  echo "[$(date -Is)] R fit"
  run_env Rscript "${FIT_R}" "${BINNED}" "${OUTDIR}/sequenza_fit" "${SAMPLE_ID}"
  date -Is > "${DONE_FIT}"
  echo "[$(date -Is)] sequenza fit done"
}

case "${SEQUENZA_STEP}" in
  pileup) do_pileup ;;
  fit) do_fit ;;
  all) do_pileup; do_fit ;;
  *) echo "ERROR: SEQUENZA_STEP must be pileup|fit|all" >&2; exit 2 ;;
esac
