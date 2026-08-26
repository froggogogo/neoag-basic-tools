#!/usr/bin/env bash
# =============================================================================
# sunbinbin multi-CNV orchestrator
#
# Default schedule (CNV_SCHEDULE=isolated, STAGE=all):
#   For each tool in order (still group-internal "serial over tools"):
#     pileup(tool) -> fit(tool) if pileup ready
#   Reuses existing markers / intermediates unless FORCE_*=1.
#   One tool failing does NOT stop the remaining tools
#   (CONTINUE_ON_ERROR=1 by default).
#
# Alternate schedule (CNV_SCHEDULE=phases):
#   1) SERIAL pileup of all tools, then 2) fit (parallel or serial).
#
# Resume / subset:
#   STAGE=fit bash scripts/run_cnv_all.sh
#   STAGE=pileup ...  STAGE=status ...
#   TOOLS="facets sequenza" ...
#   CONTINUE_ON_ERROR=0 ...   # old fail-fast behavior
#
# Outputs under CASE_ROOT/{facets,sequenza,purple,ascat,logs}
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_ROOT="${CASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
NEOAG_ROOT="${NEOAG_ROOT:-}"  # resolved by lib_portable_env.sh
export NEOAG_ROOT

# Templates live on neoag-100T (canonical) / shared_scripts (mirror).
# Workflow: copy templates into $CASE/scripts/, edit case.config/inputs, then run
# from SCRIPT_DIR (case-local copies). Do not exec shared paths at runtime.
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_portable_env.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_tool_timing.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_site_defaults.sh"

# ---- sample ----
PATIENT_ID="${PATIENT_ID:?export PATIENT_ID}"
TUMOR_BAM="${TUMOR_BAM:?export TUMOR_BAM}"
NORMAL_BAM="${NORMAL_BAM:?export NORMAL_BAM}"
SOMATIC_VCF="${SOMATIC_VCF:-}"
# Prefer env REF_FASTA if set+valid; otherwise NAS fallbacks (ignore broken tools.env path).
resolve_ref_fasta

# ---- dirs ----
FACETS_OUT="${FACETS_OUT:-${CASE_ROOT}/facets/omni2p5_snponly_downsample}"
SEQUENZA_OUT="${SEQUENZA_OUT:-${CASE_ROOT}/sequenza}"
PURPLE_OUT="${PURPLE_OUT:-${CASE_ROOT}/purple}"
ASCAT_OUT="${ASCAT_OUT:-${CASE_ROOT}/ascat}"
LOG_DIR="${LOG_DIR:-${CASE_ROOT}/logs}"
MASTER_LOG="${MASTER_LOG:-${LOG_DIR}/cnv_all_$(date +%Y%m%d_%H%M%S).log}"

STAGE="${STAGE:-all}"          # all|pileup|fit|status
TOOLS="${TOOLS:-facets sequenza purple ascat}"
FORCE_PILEUP="${FORCE_PILEUP:-0}"
FORCE_FIT="${FORCE_FIT:-0}"
FACETS_MODE="${FACETS_MODE:-omni2p5}"
CHUNK_JOBS="${CHUNK_JOBS:-3}"
HMF_THREADS="${HMF_THREADS:-8}"
HMFTOOLS_JVM_MEM="${HMFTOOLS_JVM_MEM:--Xmx32g}"
# 1 = a failed tool does not abort the rest (default)
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"
# isolated | phases
# isolated: per tool pileup then fit (best for resume; FACETS fit not blocked by Sequenza)
# phases: all pileups then all fits
CNV_SCHEDULE="${CNV_SCHEDULE:-isolated}"
# when CNV_SCHEDULE=phases: parallel | serial fit
FIT_PARALLEL="${FIT_PARALLEL:-1}"
export SNP_PILEUP_BIN="${SNP_PILEUP_BIN:-${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/tools/neodata_tools/FACETS/.conda/bin/snp-pileup}"

mkdir -p "${FACETS_OUT}" "${SEQUENZA_OUT}" "${PURPLE_OUT}" "${ASCAT_OUT}" "${LOG_DIR}"
TIMING_TSV="${TIMING_TSV:-${LOG_DIR}/tool_runtime.tsv}"
timing_init "${TIMING_TSV}"
exec > >(tee -a "${MASTER_LOG}") 2>&1

# Aggregate step failures (not abort if CONTINUE_ON_ERROR=1)
CNV_FAILS=0
CNV_FAILED_STEPS=()

tool_enabled() {
  [[ " ${TOOLS} " == *" $1 "* ]]
}

ts() { date -Is; }

# Run a named step; on failure record and optionally continue.
# Always return 0 when CONTINUE_ON_ERROR=1 so `set -e` never aborts the serial queue.
try_step() {
  local group="$1" tool="$2"
  shift 2
  set +e
  timing_run "${group}" "${tool}" -- "$@"
  local rc=$?
  set -e
  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi
  CNV_FAILS=$((CNV_FAILS + 1))
  CNV_FAILED_STEPS+=("${tool}")
  if [[ "${CONTINUE_ON_ERROR}" == "1" ]]; then
    echo "[$(ts)] WARN: step ${tool} failed (rc=${rc}); CONTINUE_ON_ERROR=1 -> keep going" >&2
    return 0
  fi
  echo "[$(ts)] ERROR: step ${tool} failed (rc=${rc}) and CONTINUE_ON_ERROR=0" >&2
  return 1
}

echo "================================================================"
echo "sunbinbin CNV orchestrator $(ts)"
echo "  STAGE=${STAGE}"
echo "  TOOLS=${TOOLS}"
echo "  CNV_SCHEDULE=${CNV_SCHEDULE}  CONTINUE_ON_ERROR=${CONTINUE_ON_ERROR}"
echo "  CASE_ROOT=${CASE_ROOT}"
echo "  TUMOR_BAM=${TUMOR_BAM}"
echo "  NORMAL_BAM=${NORMAL_BAM}"
echo "  SOMATIC_VCF=${SOMATIC_VCF}"
echo "  REF_FASTA=${REF_FASTA}"
echo "  MASTER_LOG=${MASTER_LOG}"
echo "================================================================"

require_inputs() {
  for f in "${TUMOR_BAM}" "${NORMAL_BAM}" "${TUMOR_BAM}.bai" "${NORMAL_BAM}.bai"; do
    [[ -s "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
  done
  [[ -s "${REF_FASTA}" ]] || { echo "ERROR: REF_FASTA missing: ${REF_FASTA}" >&2; exit 1; }
  [[ -w "${CASE_ROOT}" ]] || { echo "ERROR: CASE_ROOT not writable: ${CASE_ROOT}" >&2; exit 1; }
}

print_status() {
  local facets_pileup="${FACETS_OUT}/${PATIENT_ID}.omni2p5.snponly.pileup.csv"
  [[ "${FACETS_MODE}" == "common_snp" ]] && facets_pileup="${FACETS_OUT}/${PATIENT_ID}.common_snp.snponly.pileup.csv"
  cat <<EOF
--- marker status ---
FACETS pileup : $( [[ -s "${facets_pileup}" ]] && echo OK || echo MISSING)  ${facets_pileup}
FACETS fit    : $( [[ -s "${FACETS_OUT}/purity.tsv" ]] && echo OK || echo MISSING)  ${FACETS_OUT}/purity.tsv
Sequenza pile : $( [[ -f "${SEQUENZA_OUT}/.pileup.done" ]] && echo OK || echo MISSING)  ${SEQUENZA_OUT}/.pileup.done
Sequenza fit  : $( [[ -f "${SEQUENZA_OUT}/.fit.done" ]] && echo OK || echo MISSING)  ${SEQUENZA_OUT}/.fit.done
AMBER         : $( [[ -f "${PURPLE_OUT}/amber/.amber.done" ]] && echo OK || echo MISSING)  ${PURPLE_OUT}/amber/.amber.done
COBALT        : $( [[ -f "${PURPLE_OUT}/cobalt/.cobalt.done" ]] && echo OK || echo MISSING)  ${PURPLE_OUT}/cobalt/.cobalt.done
PURPLE fit    : $( [[ -f "${PURPLE_OUT}/purple/.fit.done" ]] && echo OK || echo MISSING)  ${PURPLE_OUT}/purple/.fit.done
ASCAT pileup  : $( [[ -f "${ASCAT_OUT}/.pileup.done" ]] && echo OK || echo MISSING)  ${ASCAT_OUT}/.pileup.done
ASCAT fit     : $( [[ -f "${ASCAT_OUT}/.fit.done" ]] && echo OK || echo MISSING)  ${ASCAT_OUT}/.fit.done
EOF
  if [[ "${CNV_FAILS}" -gt 0 ]]; then
    echo "--- failed steps this run (${CNV_FAILS}) ---"
    printf '  %s\n' "${CNV_FAILED_STEPS[@]}"
  fi
}

facets_pileup_path() {
  if [[ "${FACETS_MODE}" == "common_snp" ]]; then
    echo "${FACETS_OUT}/${PATIENT_ID}.common_snp.snponly.pileup.csv"
  else
    echo "${FACETS_OUT}/${PATIENT_ID}.omni2p5.snponly.pileup.csv"
  fi
}

facets_pileup_ready() { [[ -s "$(facets_pileup_path)" ]]; }
sequenza_pileup_ready() { [[ -f "${SEQUENZA_OUT}/.pileup.done" ]]; }
purple_pileup_ready() {
  [[ -f "${PURPLE_OUT}/amber/.amber.done" && -f "${PURPLE_OUT}/cobalt/.cobalt.done" ]]
}
ascat_pileup_ready() { [[ -f "${ASCAT_OUT}/.pileup.done" ]]; }

# -------------------- PILEUP --------------------
pileup_facets() {
  local pileup
  pileup="$(facets_pileup_path)"
  if [[ -s "${pileup}" && "${FORCE_PILEUP}" != "1" ]]; then
    echo "[$(ts)] FACETS pileup exists -> reuse ${pileup}"
    return 0
  fi
  echo "[$(ts)] FACETS pileup START"
  PATIENT_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  FACETS_MODE="${FACETS_MODE}" \
  OUTDIR="${FACETS_OUT}" \
  LOG="${FACETS_OUT}/run.pileup.log" \
  FACETS_STEP=pileup \
  SNP_PILEUP_BIN="${SNP_PILEUP_BIN}" \
  bash "${NEOAG_ROOT}/scripts/run_facets_sample.sh"
  echo "[$(ts)] FACETS pileup DONE"
}

pileup_sequenza() {
  echo "[$(ts)] Sequenza pileup START"
  SAMPLE_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  REF_FASTA="${REF_FASTA}" \
  NEOAG_REFERENCE_FASTA="${REF_FASTA}" \
  OUTDIR="${SEQUENZA_OUT}" \
  LOG="${SEQUENZA_OUT}/run.pileup.log" \
  CHUNK_JOBS="${CHUNK_JOBS}" \
  SEQUENZA_STEP=pileup \
  FORCE="${FORCE_PILEUP}" \
  bash "${SCRIPT_DIR}/run_sequenza_steps.sh"
  echo "[$(ts)] Sequenza pileup DONE"
}

pileup_purple() {
  echo "[$(ts)] PURPLE AMBER+COBALT START"
  # Do NOT force PATIENT_ID_tumor — run_purple_steps resolves VCF genotype IDs
  # by patient+tumor/blood keywords (separator-agnostic) or BAM basename tokens.
  PATIENT_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  SOMATIC_VCF="${SOMATIC_VCF}" \
  REF_FASTA="${REF_FASTA}" \
  NEOAG_REFERENCE_FASTA="${REF_FASTA}" \
  OUTDIR="${PURPLE_OUT}" \
  LOG="${PURPLE_OUT}/run.pileup.log" \
  THREADS="${HMF_THREADS}" \
  HMFTOOLS_JVM_MEM="${HMFTOOLS_JVM_MEM}" \
  PURPLE_STEP=pileup \
  FORCE="${FORCE_PILEUP}" \
  bash "${SCRIPT_DIR}/run_purple_steps.sh"
  echo "[$(ts)] PURPLE AMBER+COBALT DONE"
}

pileup_ascat() {
  local pileup
  pileup="$(facets_pileup_path)"
  if [[ ! -s "${pileup}" ]]; then
    echo "[$(ts)] WARN: ASCAT pileup skipped — need FACETS pileup first: ${pileup}" >&2
    return 1
  fi
  echo "[$(ts)] ASCAT convert-from-FACETS START"
  SAMPLE_ID="${PATIENT_ID}" \
  PILEUP="${pileup}" \
  OUTDIR="${ASCAT_OUT}" \
  LOG="${ASCAT_OUT}/run.pileup.log" \
  ASCAT_STEP=pileup \
  FORCE="${FORCE_PILEUP}" \
  bash "${SCRIPT_DIR}/run_ascat_from_facets.sh"
  echo "[$(ts)] ASCAT convert-from-FACETS DONE"
}

run_pileup_serial() {
  echo "[$(ts)] ===== PILEUP BEGIN (continue_on_error=${CONTINUE_ON_ERROR}) ====="
  tool_enabled facets && try_step cnv facets_pileup pileup_facets
  tool_enabled sequenza && try_step cnv sequenza_pileup pileup_sequenza
  tool_enabled purple && try_step cnv purple_amber_cobalt pileup_purple
  tool_enabled ascat && try_step cnv ascat_pileup pileup_ascat
  echo "[$(ts)] ===== PILEUP END fails=${CNV_FAILS} ====="
  print_status
}

# -------------------- FIT --------------------
fit_facets() {
  if ! facets_pileup_ready; then
    echo "[$(ts)] SKIP FACETS fit — pileup not ready" >&2
    return 1
  fi
  # Reuse only if purity is a real number (export used to fail with NA rows)
  if [[ -s "${FACETS_OUT}/purity.tsv" && "${FORCE_FIT}" != "1" ]]; then
    if awk -F'\t' 'NR==2 && $2+0==$2 && $2!="NA" {ok=1} END{exit !ok}' "${FACETS_OUT}/purity.tsv"; then
      echo "[$(ts)] FACETS fit exists valid purity.tsv -> reuse"
      return 0
    fi
    echo "[$(ts)] FACETS purity.tsv is NA/invalid -> re-export/refit"
  fi
  local flog="${FACETS_OUT}/run.fit.log"
  # Prefer real R extractor (not bin/runFACETS.R bash shim)
  local facets_home="${FACETS_HOME:-${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/tools/facets}"
  echo "[$(ts)] FACETS fit START (omni2p5) -> ${flog}"
  PATIENT_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  FACETS_MODE=omni2p5 \
  OUTDIR="${FACETS_OUT}" \
  LOG="${flog}" \
  FACETS_HOME="${facets_home}" \
  FACETS_STEP=downsample \
  bash "${NEOAG_ROOT}/scripts/run_facets_sample.sh"
  PATIENT_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  FACETS_MODE=omni2p5 \
  OUTDIR="${FACETS_OUT}" \
  LOG="${flog}" \
  FACETS_HOME="${facets_home}" \
  FACETS_STEP=fit \
  bash "${NEOAG_ROOT}/scripts/run_facets_sample.sh"
  PATIENT_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  FACETS_MODE=omni2p5 \
  OUTDIR="${FACETS_OUT}" \
  LOG="${flog}" \
  FACETS_HOME="${facets_home}" \
  FACETS_STEP=export \
  bash "${NEOAG_ROOT}/scripts/run_facets_sample.sh"
  echo "[$(ts)] FACETS fit DONE"
}

fit_sequenza() {
  if ! sequenza_pileup_ready; then
    echo "[$(ts)] SKIP Sequenza fit — pileup not ready" >&2
    return 1
  fi
  if [[ -f "${SEQUENZA_OUT}/.fit.done" && "${FORCE_FIT}" != "1" ]]; then
    echo "[$(ts)] Sequenza fit .fit.done exists -> reuse"
    return 0
  fi
  echo "[$(ts)] Sequenza fit START"
  SAMPLE_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  REF_FASTA="${REF_FASTA}" \
  NEOAG_REFERENCE_FASTA="${REF_FASTA}" \
  OUTDIR="${SEQUENZA_OUT}" \
  LOG="${SEQUENZA_OUT}/run.fit.log" \
  SEQUENZA_STEP=fit \
  FORCE="${FORCE_FIT}" \
  bash "${SCRIPT_DIR}/run_sequenza_steps.sh"
  echo "[$(ts)] Sequenza fit DONE"
}

fit_purple() {
  if ! purple_pileup_ready; then
    echo "[$(ts)] SKIP PURPLE fit — AMBER/COBALT not ready" >&2
    return 1
  fi
  if [[ -f "${PURPLE_OUT}/purple/.fit.done" && "${FORCE_FIT}" != "1" ]]; then
    echo "[$(ts)] PURPLE fit .fit.done exists -> reuse"
    return 0
  fi
  echo "[$(ts)] PURPLE fit START"
  # Sample IDs resolved inside run_purple_steps (VCF keywords / BAM tokens).
  PATIENT_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  SOMATIC_VCF="${SOMATIC_VCF}" \
  REF_FASTA="${REF_FASTA}" \
  NEOAG_REFERENCE_FASTA="${REF_FASTA}" \
  OUTDIR="${PURPLE_OUT}" \
  LOG="${PURPLE_OUT}/run.fit.log" \
  THREADS="${HMF_THREADS}" \
  HMFTOOLS_JVM_MEM="${HMFTOOLS_JVM_MEM}" \
  PURPLE_STEP=fit \
  FORCE="${FORCE_FIT}" \
  bash "${SCRIPT_DIR}/run_purple_steps.sh"
  echo "[$(ts)] PURPLE fit DONE"
}

fit_ascat() {
  if ! ascat_pileup_ready; then
    echo "[$(ts)] SKIP ASCAT fit — pileup not ready" >&2
    return 1
  fi
  if [[ -f "${ASCAT_OUT}/.fit.done" && "${FORCE_FIT}" != "1" ]]; then
    echo "[$(ts)] ASCAT fit .fit.done exists -> reuse"
    return 0
  fi
  echo "[$(ts)] ASCAT fit START"
  SAMPLE_ID="${PATIENT_ID}" \
  PILEUP="$(facets_pileup_path)" \
  OUTDIR="${ASCAT_OUT}" \
  LOG="${ASCAT_OUT}/run.fit.log" \
  ASCAT_STEP=fit \
  FORCE="${FORCE_FIT}" \
  bash "${SCRIPT_DIR}/run_ascat_from_facets.sh"
  echo "[$(ts)] ASCAT fit DONE"
}

run_fit_serial() {
  echo "[$(ts)] ===== FIT SERIAL BEGIN ====="
  tool_enabled facets && try_step cnv facets_fit fit_facets
  tool_enabled sequenza && try_step cnv sequenza_fit fit_sequenza
  tool_enabled purple && try_step cnv purple_fit fit_purple
  tool_enabled ascat && try_step cnv ascat_fit fit_ascat
  echo "[$(ts)] ===== FIT SERIAL END fails=${CNV_FAILS} ====="
  print_status
}

run_fit_parallel() {
  echo "[$(ts)] ===== FIT PARALLEL BEGIN ====="
  local pids=()
  local names=()
  local starts=()
  local fails=0

  run_bg() {
    local name="$1"
    shift
    local log="${LOG_DIR}/fit_${name}.log"
    echo "[$(ts)] launch fit:${name} log=${log}"
    starts+=("$(date +%s)")
    (
      set -euo pipefail
      "$@"
    ) >"${log}" 2>&1 &
    pids+=("$!")
    names+=("${name}")
  }

  tool_enabled facets && facets_pileup_ready && run_bg facets fit_facets
  tool_enabled sequenza && sequenza_pileup_ready && run_bg sequenza fit_sequenza
  tool_enabled purple && purple_pileup_ready && run_bg purple fit_purple
  tool_enabled ascat && ascat_pileup_ready && run_bg ascat fit_ascat

  if [[ ${#pids[@]} -eq 0 ]]; then
    echo "WARN: no fit jobs launched (missing pileups or TOOLS empty)"
    print_status
    return 0
  fi

  local i end_epoch
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      end_epoch="$(date +%s)"
      timing_record_epochs cnv "${names[$i]}_fit" ok "${starts[$i]}" "${end_epoch}" ""
      echo "[$(ts)] fit:${names[$i]} OK"
    else
      end_epoch="$(date +%s)"
      timing_record_epochs cnv "${names[$i]}_fit" failed "${starts[$i]}" "${end_epoch}" "see ${LOG_DIR}/fit_${names[$i]}.log"
      echo "[$(ts)] fit:${names[$i]} FAILED (see ${LOG_DIR}/fit_${names[$i]}.log)" >&2
      fails=$((fails + 1))
      CNV_FAILS=$((CNV_FAILS + 1))
      CNV_FAILED_STEPS+=("${names[$i]}_fit")
    fi
  done

  echo "[$(ts)] ===== FIT PARALLEL END fails=${fails} ====="
  print_status
  if [[ "${CONTINUE_ON_ERROR}" == "1" ]]; then
    return 0
  fi
  [[ "${fails}" -eq 0 ]]
}

# Per-tool: reuse pileup if present, then fit when ready. One tool's crash never blocks others.
run_isolated_serial() {
  echo "[$(ts)] ===== ISOLATED serial (pileup->fit per tool) BEGIN continue_on_error=${CONTINUE_ON_ERROR} ====="
  local tool
  for tool in facets sequenza purple ascat; do
    tool_enabled "${tool}" || continue
    echo "[$(ts)] ---- tool=${tool} ----"
    # Isolate each tool so unexpected set -e deaths in subshells cannot skip remaining tools.
    set +e
    case "${tool}" in
      facets)
        try_step cnv facets_pileup pileup_facets
        if facets_pileup_ready; then
          try_step cnv facets_fit fit_facets
        else
          echo "[$(ts)] SKIP facets fit (no pileup)"
        fi
        ;;
      sequenza)
        try_step cnv sequenza_pileup pileup_sequenza
        if sequenza_pileup_ready; then
          try_step cnv sequenza_fit fit_sequenza
        else
          echo "[$(ts)] SKIP sequenza fit (no pileup)"
        fi
        ;;
      purple)
        try_step cnv purple_amber_cobalt pileup_purple
        if purple_pileup_ready; then
          try_step cnv purple_fit fit_purple
        else
          echo "[$(ts)] SKIP purple fit (AMBER/COBALT incomplete)"
        fi
        ;;
      ascat)
        try_step cnv ascat_pileup pileup_ascat
        if ascat_pileup_ready; then
          try_step cnv ascat_fit fit_ascat
        else
          echo "[$(ts)] SKIP ascat fit (no ascat pileup)"
        fi
        ;;
    esac
    set -e
  done
  echo "[$(ts)] ===== ISOLATED serial END fails=${CNV_FAILS} ====="
  print_status
}

finalize_exit() {
  echo "[$(ts)] orchestrator finished STAGE=${STAGE} fails=${CNV_FAILS}"
  if [[ "${#CNV_FAILED_STEPS[@]}" -gt 0 ]]; then
    echo "[$(ts)] failed steps: ${CNV_FAILED_STEPS[*]}"
  fi
  if [[ "${CONTINUE_ON_ERROR}" == "1" ]]; then
    # Partial success is OK for resume runs; caller inspects markers/status.
    return 0
  fi
  [[ "${CNV_FAILS}" -eq 0 ]]
}

# -------------------- main --------------------
case "${STAGE}" in
  status)
    print_status
    ;;
  pileup)
    require_inputs
    run_pileup_serial
    finalize_exit
    ;;
  fit)
    require_inputs
    echo "[$(ts)] Fit-only mode: will NOT re-run pileups; tools without pileup are skipped"
    print_status
    if [[ "${FIT_PARALLEL}" == "1" ]]; then
      run_fit_parallel
    else
      run_fit_serial
    fi
    finalize_exit
    ;;
  all)
    require_inputs
    if [[ "${CNV_SCHEDULE}" == "phases" ]]; then
      run_pileup_serial
      if [[ "${FIT_PARALLEL}" == "1" ]]; then
        run_fit_parallel
      else
        run_fit_serial
      fi
    else
      run_isolated_serial
    fi
    finalize_exit
    ;;
  *)
    echo "ERROR: STAGE must be all|pileup|fit|status" >&2
    exit 2
    ;;
esac
