#!/usr/bin/env bash
# CNV queue: FACETS / Sequenza / PURPLE / ASCAT serial internally.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

if marker_done "${CASE_ROOT}/evidence/.cnv.done" || [[ -s "${CASE_ROOT}/evidence/purity.tsv" ]]; then
  if [[ "${FORCE:-0}" != "1" && -s "${CASE_ROOT}/evidence/purity.tsv" ]]; then
    ok "CNV/purity already present"
    exit 0
  fi
fi

if w="$(find_wrapper cnv_all || true)"; then
  bash "$w"
elif w="$(find_wrapper cnv_hla_parallel || true)"; then
  RUN_CNV=1 RUN_HLA=0 bash "$w"
else
  die "NO_WRAPPER" "请提供 ${CASE_ROOT}/scripts/run_cnv_all.sh。内部串行 FACETS→Sequenza→PURPLE→ASCAT；与 HLA 队列对外并行。"
fi
ok "CNV queue finished"
