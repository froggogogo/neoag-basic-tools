#!/usr/bin/env bash
# Portable Sequenza pileup + fit — aligned with sunbinbin gold standard
# (sunbinbin/scripts/run_sequenza_steps.sh md5 80cb04e4 path; merge output = fake .gz).
#
# pileup: per-chrom bam2seqz (NUL-safe) → per-chrom seqz_binning → merge binned
#         with awk empty-line / duplicate-header filter → ${SAMPLE}.small.seqz.gz
#         as PLAIN TSV named .gz (+ hardlink twin without .gz). Never | gzip -c.
# fit:    chrom-split fread Rscript on fake-.gz plain text (no gunzip in fit).
#
# Do NOT concat raw chrom seqz then bin: missing newlines at chr boundaries
# produce >14 fields; adding printf '\n' without awk creates empty lines (NF=1)
# and seqz_binning raises ValueError (expected 14, got 1).
#
# Fake .gz: sequenza-utils seqz_binning and this merge write plain TSV named *.gz
# (sunbinbin successful artifact). Real gzip small.seqz.gz is rejected by fit.
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
  # Prefer case-local / template next to this script, then DEPS copies.
  # Do NOT prefer stale DEPS/src/neo first — that predates template→case model.
  for r in \
    "${_SCRIPT_DIR}/run_sequenza_fit.R" \
    "${_SCRIPT_DIR}/../../patches/run_sequenza_fit.fread.R" \
    "${DEPS_DIR}/shared_scripts/sequenza/run_sequenza_fit.R" \
    "${DEPS_DIR}/tools/sequenza/run_sequenza_fit.R" \
    "${DEPS_DIR}/scripts/patches/run_sequenza_fit.fread.R" \
    "${DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R"
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
  local c
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
BINNED="${OUTDIR}/${SAMPLE_ID}.small.seqz.gz"
DONE_PILEUP="${OUTDIR}/.pileup.done"
DONE_FIT="${OUTDIR}/.fit.done"

mkdir -p "${OUTDIR}/chrom" "${OUTDIR}/chrom_binned" "${OUTDIR}/sequenza_fit" "${OUTDIR}/tmp" "$(dirname "${LOG}")"
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
echo "    path=per-chrom-bin+merge-binned (sunbinbin gold; fake .gz accepted)"

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

# Accept real gzip OR plain TSV named .gz (seqz_binning often emits fake .gz).
# aligned with sunbinbin gold path; accept fake .gz like R fit (β policy)
is_usable_seqz() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  if gzip -t "$f" 2>/dev/null; then
    return 0
  fi
  # plain TSV: header or first data row
  local head1
  head1="$(head -n 1 "$f" 2>/dev/null || true)"
  [[ "${head1}" == chromosome$'\t'* || "${head1}" == chr* ]]
}

# Stream seqz whether real gzip or plain text.
cat_seqz() {
  local f="$1"
  if gzip -t "$f" 2>/dev/null; then
    gzip -dc "$f"
  else
    cat "$f"
  fi
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

bin_one_chrom() {
  local chrom="$1"
  local safe
  safe="$(echo "${chrom}" | tr ':/-' '___')"
  local seqz="${OUTDIR}/chrom/${SAMPLE_ID}.${safe}.seqz.gz"
  local small="${OUTDIR}/chrom_binned/${SAMPLE_ID}.${safe}.small.seqz.gz"
  # reuse if real gzip OR usable fake .gz (β)
  if [[ -s "${small}" && "${FORCE}" != "1" ]] && is_usable_seqz "${small}"; then
    echo "[$(date -Is)] reuse binned ${chrom} -> ${small}"
    return 0
  fi
  echo "[$(date -Is)] seqz_binning ${chrom}"
  "${SEQUENZA_BIN}/sequenza-utils" seqz_binning \
    -s "${seqz}" -w "${BIN_WINDOW}" -T "${TABIX}" -o "${small}.tmp"
  if ! is_usable_seqz "${small}.tmp"; then
    echo "ERROR: seqz_binning produced unusable output for ${chrom}: ${small}.tmp" >&2
    rm -f "${small}.tmp"
    return 1
  fi
  mv "${small}.tmp" "${small}"
}

do_pileup() {
  if [[ -s "${BINNED}" && -f "${DONE_PILEUP}" && "${FORCE}" != "1" ]] && is_usable_seqz "${BINNED}"; then
    echo "[$(date -Is)] sequenza pileup already done -> ${BINNED}"
    return 0
  fi
  export -f run_chrom bin_one_chrom is_usable_seqz cat_seqz
  export SAMPLE_ID TUMOR_BAM NORMAL_BAM REF GC OUTDIR SAMTOOLS TABIX QLIMIT MIN_DEPTH_N HOM HET FORCE
  export SEQUENZA_PY BAM2SEQZ_WRAP BIN_WINDOW SEQUENZA_BIN
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
    # (hardening kept from post-gold shared revision; not in original sunbinbin file)
    last_nf="$(zcat "$f" | tail -n 1 | awk -F'\t' '{print NF}')"
    if [[ "${last_nf}" != "14" ]]; then
      echo "ERROR truncated/bad last line NF=${last_nf} in $f (need 14); delete and re-run bam2seqz" >&2
      exit 1
    fi
  done

  # Bin per chromosome then merge small seqz (sunbinbin gold).
  echo "[$(date -Is)] seqz_binning per chromosome"
  mkdir -p "${OUTDIR}/chrom_binned"
  # shellcheck disable=SC2086
  printf "%s\n" ${CHROMS} | xargs -I{} -P "${CHUNK_JOBS}" bash -c "bin_one_chrom \"{}\""

  echo "[$(date -Is)] merge binned seqz -> ${BINNED}"
  {
    first=1
    for chrom in ${CHROMS}; do
      safe="$(echo "${chrom}" | tr ':/-' '___')"
      f="${OUTDIR}/chrom_binned/${SAMPLE_ID}.${safe}.small.seqz.gz"
      [[ -s "$f" ]] || { echo "ERROR missing binned $f" >&2; exit 1; }
      if [[ "$first" == 1 ]]; then
        cat_seqz "$f"
        first=0
      else
        cat_seqz "$f" | tail -n +2
      fi
      # guarantee a newline between chroms even if a file omits the last NL
      printf '\n'
    done
  # sunbinbin β: write plain TSV named *.small.seqz.gz (NOT real gzip).
  # seqz_binning per-chrom outputs are already fake .gz; R fit awk-split expects text.
  } | awk 'NF==0{next} /^chromosome/{if(seen++) next} {print}' > "${BINNED}.tmp"
  [[ -s "${BINNED}.tmp" ]] || { echo "ERROR: empty merged binned seqz" >&2; exit 1; }
  mv "${BINNED}.tmp" "${BINNED}"
  plain="${BINNED%.gz}"
  if [[ "${plain}" != "${BINNED}" ]]; then
    rm -f "${plain}"
    ln "${BINNED}" "${plain}" 2>/dev/null || cp -a "${BINNED}" "${plain}"
  fi
  date -Is > "${DONE_PILEUP}"
  echo "[$(date -Is)] sequenza pileup done (per-chrom bin + merge small; fake .gz like sunbinbin)"
}

do_fit() {
  [[ -s "${BINNED}" ]] || { echo "ERROR: missing ${BINNED}; run SEQUENZA_STEP=pileup first" >&2; exit 1; }
  if gzip -t "${BINNED}" 2>/dev/null; then
    echo "ERROR: ${BINNED} is real gzip; remake merge as sunbinbin fake .gz (plain TSV named .gz)" >&2
    exit 1
  fi
  if [[ -f "${DONE_FIT}" && -s "${OUTDIR}/sequenza_fit/${SAMPLE_ID}.sequenza_summary.tsv" && "${FORCE}" != "1" ]]; then
    echo "[$(date -Is)] sequenza fit already done"
    return 0
  fi
  rm -f "${DONE_FIT}"
  echo "[$(date -Is)] R fit (fake .gz plain text)"
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
