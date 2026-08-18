#!/usr/bin/env bash
# Built-in short-bulk RNA orchestrator.
#
# Independent (needed downstream, EasyFuse does not publish them):
#   STAR BAM → RegTools / SNAF / pVACsplice
#   Arriba + STAR-Fusion native tables → pVACfuse
# EasyFuse: fusion meta (includes FusionCatcher internally; do NOT run FC standalone).
#
# Per-tool scripts come from the case via find_wrapper (sunbinbin-style).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${RUN_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${RUN_DIR}/lib/dispatch.sh"

SHORT_RNA_ROOT="${CASE_ROOT}/short-rna"
STAGE="${STAGE:-all}"
FORCE="${FORCE:-0}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"
CAP_LOAD="${CAP_LOAD:-18}"
MIN_AVAIL_MEM_G="${MIN_AVAIL_MEM_G:-24}"
SKIP_IF_BUSY="${SKIP_IF_BUSY:-0}"

export SHORT_RNA_ROOT PATIENT_ID="${PATIENT_ID:-${SAMPLE_ID}}"
export TMPDIR="${TMPDIR:-${SHORT_RNA_ROOT}/tmp}"
export TMP="${TMPDIR}" TEMP="${TMPDIR}"
mkdir -p "${SHORT_RNA_ROOT}/logs" "${TMPDIR}" "${SHORT_RNA_ROOT}/evidence"

MASTER_LOG="${MASTER_LOG:-${SHORT_RNA_ROOT}/logs/short_rna_${STAGE}_$(date +%Y%m%d_%H%M%S).log}"
exec > >(tee -a "${MASTER_LOG}") 2>&1

RNA_FAILS=0
RNA_FAILED_STEPS=()
RNA_SKIPPED_STEPS=()

ts() { date -Is; }

load1() { awk '{printf "%.0f", $1}' /proc/loadavg; }
avail_mem_g() { free -g | awk '/^Mem:/{print $7}'; }

resource_ok_or_wait() {
  local need_msg="$1"
  local load avail
  load="$(load1)"; avail="$(avail_mem_g)"
  if [[ "${load}" -ge "${CAP_LOAD}" ]]; then
    echo "[$(ts)] WARN: loadavg1=${load} >= CAP_LOAD=${CAP_LOAD}; ${need_msg}" >&2
    [[ "${SKIP_IF_BUSY}" == "1" ]] && { RNA_SKIPPED_STEPS+=("${need_msg}:busy"); return 1; }
  fi
  if [[ "${avail}" -lt "${MIN_AVAIL_MEM_G}" ]]; then
    echo "[$(ts)] WARN: avail_mem=${avail}G < MIN=${MIN_AVAIL_MEM_G}; ${need_msg}" >&2
    [[ "${SKIP_IF_BUSY}" == "1" ]] && { RNA_SKIPPED_STEPS+=("${need_msg}:busy"); return 1; }
  fi
  return 0
}

record_fail() {
  local tool="$1" rc="$2"
  RNA_FAILS=$((RNA_FAILS + 1))
  RNA_FAILED_STEPS+=("${tool}(rc=${rc})")
  echo "[$(ts)] WARN: tool ${tool} failed rc=${rc}; CONTINUE_ON_ERROR=${CONTINUE_ON_ERROR}" >&2
}

run_tool() {
  local tool="$1"
  shift
  resource_ok_or_wait "defer ${tool}" || { RNA_SKIPPED_STEPS+=("${tool}:busy"); return 0; }
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    record_fail "${tool}" "${rc}"
    [[ "${CONTINUE_ON_ERROR}" == "1" ]] || return "${rc}"
  fi
  return 0
}

run_tool_bg() {
  local tool="$1" rcfile="$2"
  shift 2
  (
    set +e
    "$@"
    echo $? > "${rcfile}"
  ) &
  echo $!
}

wait_bg_tools() {
  local item tool rcfile rc
  wait || true
  for item in "$@"; do
    tool="${item%%:*}"
    rcfile="${item#*:}"
    rcfile="${rcfile%%:*}"
    if [[ -f "${rcfile}" ]]; then
      rc="$(cat "${rcfile}")"
    else
      rc=99
    fi
    if [[ "${rc}" != "0" ]]; then
      record_fail "${tool}" "${rc}"
    else
      echo "[$(ts)] BG tool ${tool} OK"
    fi
  done
  if [[ "${CONTINUE_ON_ERROR}" != "1" && "${RNA_FAILS}" -gt 0 ]]; then
    return 1
  fi
  return 0
}

invoke_wrapper() {
  local stem="$1"
  local w
  w="$(find_wrapper "$stem")" || return 1
  log "rna ${stem} -> ${w}"
  bash "$w"
}

run_stem() {
  local stem
  for stem in "$@"; do
    if invoke_wrapper "$stem"; then
      return 0
    fi
  done
  echo "[$(ts)] WARN: no wrapper for $*" >&2
  RNA_SKIPPED_STEPS+=("${1}:no_wrapper")
  return 1
}

wave1_star_and_starfusion() {
  echo "[$(ts)] ===== WAVE1: Salmon + STAR ∥ STAR-Fusion ====="
  run_tool salmon run_stem salmon

  local rcdir="${SHORT_RNA_ROOT}/logs/bg_rc_wave1_$$"
  mkdir -p "${rcdir}"
  local star_rc="${rcdir}/star.rc" sf_rc="${rcdir}/star_fusion.rc"

  echo "[$(ts)] launching STAR in background"
  run_tool_bg star "${star_rc}" run_stem star
  echo "[$(ts)] launching STAR-Fusion in background"
  run_tool_bg star_fusion "${sf_rc}" run_stem star_fusion star-fusion
  echo "[$(ts)] waiting WAVE1 background jobs ..."
  wait_bg_tools "star:${star_rc}" "star_fusion:${sf_rc}"
}

wave2_arriba_regtools() {
  echo "[$(ts)] ===== WAVE2: Arriba ∥ RegTools ====="
  if [[ ! -s "${SHORT_RNA_ROOT}/star/Aligned.sortedByCoord.out.bam" ]]; then
    echo "[$(ts)] WARN: STAR BAM missing — skip Arriba/RegTools"
    RNA_SKIPPED_STEPS+=("arriba:no_bam" "regtools:no_bam")
    return 0
  fi
  local rcdir="${SHORT_RNA_ROOT}/logs/bg_rc_wave2_$$"
  mkdir -p "${rcdir}"
  local a_rc="${rcdir}/arriba.rc" r_rc="${rcdir}/regtools.rc"
  run_tool_bg arriba "${a_rc}" run_stem arriba
  run_tool_bg regtools "${r_rc}" run_stem regtools
  wait_bg_tools "arriba:${a_rc}" "regtools:${r_rc}"
}

wave3_easyfuse_rsem() {
  echo "[$(ts)] ===== WAVE3: EasyFuse → RSEM (no standalone FusionCatcher) ====="
  if ! is_ubuntu_2204; then
    echo "[$(ts)] ERROR: EasyFuse requires Ubuntu 22.04" >&2
    record_fail easyfuse 2
  else
    run_tool easyfuse run_stem easyfuse
  fi
  run_tool rsem run_stem rsem
}

wave4_pvacfuse() {
  echo "[$(ts)] ===== WAVE4: pVACfuse (Arriba + STAR-Fusion if present) ====="
  run_tool pvacfuse run_stem pvacfuse
}

wave5_pvacsplice() {
  echo "[$(ts)] ===== WAVE5: cis-splice → pVACsplice ====="
  run_tool cis_splice run_stem cis_splice cis-splice
  run_tool pvacsplice run_stem pvacsplice
}

run_evidence() {
  echo "[$(ts)] ===== EVIDENCE SUMMARY ====="
  if invoke_wrapper evidence_summary; then
    return 0
  fi
  if w="$(find_wrapper evidence || true)"; then
    bash "$w"
    return 0
  fi
  echo "[$(ts)] WARN: no evidence_summary wrapper" >&2
  RNA_SKIPPED_STEPS+=("evidence:no_wrapper")
  return 0
}

print_status() {
  local mark
  mark() { [[ -f "$1" ]] && echo OK || echo MISSING; }
  cat <<EOF
--- short-RNA marker status ---
SHORT_RNA_ROOT : ${SHORT_RNA_ROOT}
Salmon         : $(mark "${SHORT_RNA_ROOT}/salmon/.salmon.done")
STAR           : $(mark "${SHORT_RNA_ROOT}/star/.star.done")
STAR-Fusion    : $(mark "${SHORT_RNA_ROOT}/star-fusion/.star_fusion.done")
Arriba         : $(mark "${SHORT_RNA_ROOT}/arriba/.arriba.done")
EasyFuse       : $(mark "${SHORT_RNA_ROOT}/easyfuse/.easyfuse.done")
RegTools       : $(mark "${SHORT_RNA_ROOT}/regtools/.regtools.done")
RSEM           : $(mark "${SHORT_RNA_ROOT}/rsem/.rsem.done")
pVACfuse       : $(mark "${SHORT_RNA_ROOT}/pvacfuse/.pvacfuse.done")
pVACsplice     : $(mark "${SHORT_RNA_ROOT}/pvacsplice/.pvacsplice.done")
FusionCatcher  : skipped (EasyFuse only)
fails this run : ${RNA_FAILS}
EOF
}

run_all() {
  wave1_star_and_starfusion
  wave2_arriba_regtools
  wave3_easyfuse_rsem
  wave4_pvacfuse
  wave5_pvacsplice
  run_evidence
  print_status
}

echo "================================================================"
echo "neoag short-RNA MASTER $(ts)"
echo "  STAGE=${STAGE} FORCE=${FORCE} CONTINUE_ON_ERROR=${CONTINUE_ON_ERROR}"
echo "  SHORT_RNA_ROOT=${SHORT_RNA_ROOT}"
echo "  MASTER_LOG=${MASTER_LOG}"
echo "================================================================"

case "${STAGE}" in
  status) print_status ;;
  all) run_all ;;
  wave1|star) wave1_star_and_starfusion; print_status ;;
  wave2|arriba) wave2_arriba_regtools; print_status ;;
  wave3|easyfuse) wave3_easyfuse_rsem; print_status ;;
  wave4|pvacfuse) wave4_pvacfuse; print_status ;;
  wave5|pvacsplice) wave5_pvacsplice; print_status ;;
  salmon) run_tool salmon run_stem salmon; print_status ;;
  star_fusion|star-fusion) run_tool star_fusion run_stem star_fusion star-fusion; print_status ;;
  regtools) run_tool regtools run_stem regtools; print_status ;;
  rsem) run_tool rsem run_stem rsem; print_status ;;
  evidence) run_evidence; print_status ;;
  fusioncatcher)
    echo "[$(ts)] SKIP FusionCatcher standalone — use EasyFuse only" >&2
    RNA_SKIPPED_STEPS+=("fusioncatcher:easyfuse_only")
    print_status
    ;;
  *)
    echo "ERROR: STAGE must be status|all|wave1-5|salmon|star|star_fusion|arriba|easyfuse|regtools|rsem|pvacfuse|pvacsplice|evidence" >&2
    exit 2
    ;;
esac

echo "[$(ts)] short-RNA MASTER finished STAGE=${STAGE} fails=${RNA_FAILS}"
if [[ "${CONTINUE_ON_ERROR}" == "1" ]]; then
  exit 0
fi
[[ "${RNA_FAILS}" -eq 0 ]]
