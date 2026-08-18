#!/usr/bin/env bash
# RNA: STAR + Arriba + STAR-Fusion independently (BAM / pVACfuse);
# EasyFuse for fusion meta (FusionCatcher only inside EasyFuse).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

MASTER="${SCRIPT_DIR}/tools/rna/run_short_rna_master.sh"
if [[ -f "$MASTER" ]]; then
  log "RNA via built-in master (STAR/Arriba/STAR-Fusion + EasyFuse; no standalone FusionCatcher)"
  STAGE=all CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}" FORCE="${FORCE:-0}" bash "$MASTER"
  exit $?
fi

if w="$(find_wrapper short_rna_all || true)"; then
  warn "built-in RNA master missing; falling back to case wrapper ${w}"
  STAGE=all CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}" bash "$w"
  exit $?
fi

if [[ -f "${CASE_ROOT}/run_short_rna.sh" ]]; then
  warn "built-in RNA master missing; falling back to ${CASE_ROOT}/run_short_rna.sh"
  STAGE=all CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}" bash "${CASE_ROOT}/run_short_rna.sh"
  exit $?
fi

die "NO_RNA_MASTER" "找不到内置 RNA master（${MASTER}）。融合仅跑 EasyFuse；病例需提供 salmon/easyfuse/regtools 等 per-tool wrapper。"
