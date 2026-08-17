#!/usr/bin/env bash
# SpliceMutr: SNAF txt → TSV → RDS → transcripts → peptides → NetMHCpan
# Prefers ops/case wrapper; else run_splicemutr_patient.sh if present.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

SM="${CASE_ROOT}/short-rna/splicemutr"
if marker_done "${SM}/.splicemutr_patient_complete" || marker_done "${SM}/.splicemutr.done"; then
  ok "SpliceMutr already done"
  exit 0
fi

if w="$(find_wrapper splicemutr_patient || find_wrapper splicemutr || true)"; then
  export SAMPLE="${SAMPLE_ID}"
  export WORK="${SM}"
  export SNAF_RESULT="${CASE_ROOT}/short-rna/snaf"
  export GTF="${NEOAG_SHARED_REF_DIR:-${DEPS_DIR}/refs}/hg38/gencode.gtf"
  [[ -s "$GTF" ]] || GTF="${DEPS_DIR}/refs/hg38/gencode.gtf"
  export SPLICEMUTR_HOME="${NEOAG_SPLICEMUTR_HOME:-${DEPS_DIR}/tools/SpliceMutr}"
  export CONDA="${CONDA_EXE:-${DEPS_DIR}/software/miniforge3/bin/conda}"
  export ENV="${NEOAG_CONDA_BASE:-${DEPS_DIR}/software/miniforge3}/envs/neoag-splicemutr"
  export NETMHCPAN="${NETMHCPAN:-${DEPS_DIR}/licenses/predictors/netMHCpan/netMHCpan}"
  bash "$w"
  exit $?
fi

warn "无 SpliceMutr wrapper。需要 run_splicemutr_patient.sh + prepare_splicemutr_candidates.py（SNAF txt→RDS）。"
exit 0
