#!/usr/bin/env bash
# =============================================================================
# run_case_all.sh — 通用病例一键总控（134 gold path）
#
# 仅通过 case.config.sh 切换病人；脚本本身零硬编码样本路径。
#
# 阶段:
#   1. DNA prereq   — run_cnv_hla_parallel.sh + run_lohhla.sh
#   2. DNA downstream — run_dna_all.sh STAGE=downstream
#   3. short-RNA    — short-rna/scripts/run_short_rna_all.sh
#   4. SNAF         — shared_scripts/snaf/run_snaf_pipeline.sh
#   5. SpliceMutr   — shared_scripts/splicemutr/run_splicemutr_patient.sh
#   6. production   — 仅 RUN_PRODUCTION=1
#
# 用法:
#   bash run_case_all.sh
#   STAGE=dna_prereq bash run_case_all.sh
#   CASE_CONFIG=/path/to/case.config.sh bash run_case_all.sh
#
# 环境: source load_config → bootstrap_case site.env
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# When symlinked into CASE_ROOT, find universal-pipeline root
UNI_ROOT="$(cd "${SCRIPT_DIR}/.." 2>/dev/null && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/load_config.sh" ]]; then
  UNI_ROOT="${SCRIPT_DIR}/.."
elif [[ -f "${UNI_ROOT}/scripts/lib/load_config.sh" ]]; then
  :
else
  UNI_ROOT="/mnt/neoag_100T/majiaxin/neoag-universal-pipeline"
fi

# shellcheck source=/dev/null
source "${UNI_ROOT}/scripts/lib/load_config.sh" "${CASE_CONFIG:-${CASE_ROOT}/case.config.sh}"

STAGE="${STAGE:-all}"
STAMP="$(date +%Y%m%d_%H%M%S)"
MASTER_LOG="${LOG_DIR}/case_all_${STAMP}.log"
exec > >(tee -a "${MASTER_LOG}") 2>&1

SHARED="${SHARED_SCRIPTS:-/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts}"
CASE_SCRIPTS="${CASE_ROOT}/scripts"

echo "================================================================"
echo "run_case_all $(date -Is) STAGE=${STAGE}"
echo "  PATIENT_ID=${PATIENT_ID}"
echo "  CASE_ROOT=${CASE_ROOT}"
echo "  MASTER_LOG=${MASTER_LOG}"
echo "================================================================"

_run_dna_prereq() {
  [[ "${RUN_DNA_PREREQ:-1}" == "1" ]] || { echo "SKIP DNA prereq (RUN_DNA_PREREQ=0)"; return 0; }
  echo "===== DNA prereq: CNV||HLA ====="
  bash "${CASE_SCRIPTS}/run_cnv_hla_parallel.sh"
  if [[ ! -f "${CASE_ROOT}/lohhla/.lohhla.done" ]]; then
    echo "===== LOHHLA ====="
    LOHHLA_STEP=lohhla bash "${CASE_SCRIPTS}/run_lohhla.sh"
  else
    echo "LOHHLA already done"
  fi
}

_run_dna_downstream() {
  [[ "${RUN_DNA_DOWNSTREAM:-1}" == "1" ]] || { echo "SKIP DNA downstream"; return 0; }
  echo "===== DNA downstream ====="
  STAGE=downstream bash "${CASE_SCRIPTS}/run_dna_all.sh"
}

_run_short_rna() {
  [[ "${RUN_SHORT_RNA:-1}" == "1" ]] || { echo "SKIP short-RNA"; return 0; }
  [[ -f "${SHORT_RNA_ROOT}/inputs.env.sh" ]] || {
    echo "WARN: no ${SHORT_RNA_ROOT}/inputs.env.sh — skip RNA" >&2
    return 0
  }
  # shellcheck disable=SC1090
  source "${SHORT_RNA_ROOT}/inputs.env.sh"
  echo "===== short-RNA ====="
  bash "${SHORT_RNA_ROOT}/scripts/run_short_rna_all.sh"
}

_run_snaf() {
  [[ "${RUN_SNAF:-1}" == "1" ]] || { echo "SKIP SNAF"; return 0; }
  [[ -x "${SHARED}/snaf/run_snaf_pipeline.sh" ]] || {
    echo "WARN: missing ${SHARED}/snaf/run_snaf_pipeline.sh" >&2
    return 0
  }
  echo "===== SNAF ====="
  bash "${SHARED}/snaf/run_snaf_pipeline.sh"
}

_run_splicemutr() {
  [[ "${RUN_SPLICEMUTR:-1}" == "1" ]] || { echo "SKIP SpliceMutr"; return 0; }
  [[ -x "${SHARED}/splicemutr/run_splicemutr_patient.sh" ]] || {
    echo "WARN: missing splicemutr runner" >&2
    return 0
  }
  echo "===== SpliceMutr ====="
  bash "${SHARED}/splicemutr/run_splicemutr_patient.sh"
}

_run_production() {
  [[ "${RUN_PRODUCTION:-0}" == "1" ]] || { echo "SKIP production (RUN_PRODUCTION=0)"; return 0; }
  local prod
  prod="$(find "${CASE_ROOT}" -maxdepth 1 -name 'production_from_results_manifest_*' -type d 2>/dev/null | sort | tail -1)"
  if [[ -n "${prod}" && -x "${prod}/run_production.sh" ]]; then
    echo "===== production_runner ====="
    bash "${prod}/run_production.sh"
  else
    echo "WARN: no production_from_results_manifest_*/run_production.sh — skip" >&2
  fi
}

case "${STAGE}" in
  dna_prereq)   _run_dna_prereq ;;
  dna_downstream) _run_dna_downstream ;;
  rna)          _run_short_rna ;;
  snaf)         _run_snaf ;;
  splicemutr)   _run_splicemutr ;;
  production)   _run_production ;;
  all)
    _run_dna_prereq
    _run_dna_downstream
    _run_short_rna
    _run_snaf
    _run_splicemutr
    _run_production
    ;;
  *)
    echo "ERROR: STAGE must be all|dna_prereq|dna_downstream|rna|snaf|splicemutr|production" >&2
    exit 2
    ;;
esac

echo "==> run_case_all finished $(date -Is)"
