#!/usr/bin/env bash
# HLA queue: OptiType → SpecHLA → HLA-LA (serial internally).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

DONE="${CASE_ROOT}/hla/.hla_consensus.done"
if marker_done "$DONE" && [[ -s "${CASE_ROOT}/hla/hla_consensus.txt" ]]; then
  ok "HLA consensus already done"
  exit 0
fi

if w="$(find_wrapper hla_all || true)"; then
  log "HLA via ${w}"
  bash "$w"
elif w="$(find_wrapper cnv_hla_parallel || true)"; then
  log "HLA via CNV||HLA orchestrator HLA-only: ${w}"
  RUN_CNV=0 RUN_HLA=1 bash "$w"
else
  die "NO_WRAPPER" "请在 ${CASE_ROOT}/scripts/ 提供 run_hla_all.sh（或 sunbinbin 的 run_hla_all_*.sh）。队列：OptiType → SpecHLA → HLA-LA，产物 hla/hla_consensus.txt"
fi

[[ -s "${CASE_ROOT}/hla/hla_consensus.txt" ]] && touch_done "$DONE"
ok "HLA queue finished"
