#!/usr/bin/env bash
# Built-in short-bulk RNA orchestrator (EasyFuse-centric).
#
# Fusion: EasyFuse only (STAR / Arriba / STAR-Fusion / FusionCatcher run inside).
# Downstream: harvest artifacts → regtools → RSEM → pVAC* → evidence.
#
# Per-tool scripts still come from the case via find_wrapper (sunbinbin-style).
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

invoke_wrapper() {
  local stem="$1"
  local w
  w="$(find_wrapper "$stem")" || return 1
  log "rna ${stem} -> ${w}"
  bash "$w"
}

run_stem() {
  local stem="$1"
  if invoke_wrapper "$stem"; then
    return 0
  fi
  echo "[$(ts)] WARN: no wrapper for ${stem}" >&2
  RNA_SKIPPED_STEPS+=("${stem}:no_wrapper")
  return 0
}

wave_salmon() {
  echo "[$(ts)] ===== WAVE1: Salmon (quant) ====="
  run_tool salmon run_stem salmon
}

wave_easyfuse() {
  echo "[$(ts)] ===== WAVE2: EasyFuse (fusion meta: STAR/Arriba/SF/FC inside) ====="
  if ! is_ubuntu_2204; then
    echo "[$(ts)] ERROR: EasyFuse requires Ubuntu 22.04" >&2
    record_fail easyfuse 2
    return 0
  fi
  run_tool easyfuse run_stem easyfuse
  run_tool harvest FORCE="${FORCE}" bash "${SCRIPT_DIR}/harvest_easyfuse_artifacts.sh"
}

wave_regtools_rsem() {
  echo "[$(ts)] ===== WAVE3: RegTools → RSEM ====="
  run_tool regtools run_stem regtools
  run_tool rsem run_stem rsem
}

wave_pvacfuse() {
  echo "[$(ts)] ===== WAVE4: pVACfuse ====="
  run_tool pvacfuse run_stem pvacfuse
}

wave_pvacsplice() {
  echo "[$(ts)] ===== WAVE5: cis-splice → pVACsplice ====="
  run_tool cis_splice run_stem cis_splice || run_tool cis_splice run_stem cis-splice || true
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
--- short-RNA marker status (EasyFuse-centric) ---
SHORT_RNA_ROOT : ${SHORT_RNA_ROOT}
Salmon         : $(mark "${SHORT_RNA_ROOT}/salmon/.salmon.done")
EasyFuse       : $(mark "${SHORT_RNA_ROOT}/easyfuse/.easyfuse.done")
STAR BAM       : $( [[ -s "${SHORT_RNA_ROOT}/star/Aligned.sortedByCoord.out.bam" ]] && echo OK || echo MISSING )
RegTools       : $(mark "${SHORT_RNA_ROOT}/regtools/.regtools.done")
RSEM           : $(mark "${SHORT_RNA_ROOT}/rsem/.rsem.done")
pVACfuse       : $(mark "${SHORT_RNA_ROOT}/pvacfuse/.pvacfuse.done")
pVACsplice     : $(mark "${SHORT_RNA_ROOT}/pvacsplice/.pvacsplice.done")
fails this run : ${RNA_FAILS}
EOF
}

run_all() {
  wave_salmon
  wave_easyfuse
  wave_regtools_rsem
  wave_pvacfuse
  wave_pvacsplice
  run_evidence
  print_status
}

echo "================================================================"
echo "neoag short-RNA MASTER (EasyFuse-centric) $(ts)"
echo "  STAGE=${STAGE} FORCE=${FORCE} CONTINUE_ON_ERROR=${CONTINUE_ON_ERROR}"
echo "  SHORT_RNA_ROOT=${SHORT_RNA_ROOT}"
echo "  MASTER_LOG=${MASTER_LOG}"
echo "================================================================"

case "${STAGE}" in
  status) print_status ;;
  all) run_all ;;
  wave1|salmon) wave_salmon; print_status ;;
  wave2|easyfuse) wave_easyfuse; print_status ;;
  wave3) wave_regtools_rsem; print_status ;;
  wave4|pvacfuse) wave_pvacfuse; print_status ;;
  wave5|pvacsplice) wave_pvacsplice; print_status ;;
  regtools) run_tool regtools run_stem regtools; print_status ;;
  rsem) run_tool rsem run_stem rsem; print_status ;;
  harvest) run_tool harvest FORCE="${FORCE}" bash "${SCRIPT_DIR}/harvest_easyfuse_artifacts.sh"; print_status ;;
  evidence) run_evidence; print_status ;;
  *)
    echo "ERROR: STAGE must be status|all|wave1-5|salmon|easyfuse|regtools|rsem|harvest|pvacfuse|pvacsplice|evidence" >&2
    exit 2
    ;;
esac

echo "[$(ts)] short-RNA MASTER finished STAGE=${STAGE} fails=${RNA_FAILS}"
if [[ "${CONTINUE_ON_ERROR}" == "1" ]]; then
  exit 0
fi
[[ "${RNA_FAILS}" -eq 0 ]]
