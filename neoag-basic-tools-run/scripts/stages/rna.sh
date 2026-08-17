#!/usr/bin/env bash
# RNA waves after sunbinbin short-rna DAG:
#   wave1 STAR ∥ STAR-Fusion (full/dual after HLA in dual)
#   wave2 salmon / regtools / EasyFuse(22.04)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

if w="$(find_wrapper short_rna_all || true)"; then
  STAGE=all CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}" bash "$w"
  exit $?
fi

if [[ -f "${CASE_ROOT}/run_short_rna.sh" ]]; then
  STAGE=all CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}" bash "${CASE_ROOT}/run_short_rna.sh"
  exit $?
fi

die "NO_WRAPPER" "请提供 short-rna/scripts/run_short_rna_all.sh。波次：STAR∥STAR-Fusion → salmon/regtools/EasyFuse。"
