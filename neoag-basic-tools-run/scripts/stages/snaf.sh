#!/usr/bin/env bash
# SNAF: prefer the skill gold pipeline (single STAR BAM + SJ gate + start<=end).
# Do not dispatch old case wrappers that mount sample_replicate from the same BAM.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

if marker_done "${CASE_ROOT}/short-rna/snaf/.snaf.done"; then
  ok "SNAF already done"
  exit 0
fi

builtin="${SCRIPT_DIR}/tools/snaf/run_snaf_patient.sh"
if [[ -f "$builtin" ]]; then
  log "SNAF via gold pipeline ${builtin} (no fake replicate; STAR SJ gate)"
  bash "$builtin"
  touch_done "${CASE_ROOT}/short-rna/snaf/.snaf.done"
  ok "SNAF finished"
  exit 0
fi

if w="$(find_wrapper snaf || true)"; then
  warn "gold SNAF pipeline missing; falling back to ${w}"
  bash "$w"
  ok "SNAF finished"
  exit 0
fi

warn "无 SNAF gold pipeline / wrapper，跳过（SpliceMutr 需要 SNAF 文本表）"
exit 0
