#!/usr/bin/env bash
# CNV queue: FACETS / Sequenza / PURPLE / ASCAT serial internally.
# Sequenza always uses the gold runner (sunbinbin chrom-split + NUL-safe bam2seqz)
# if BAM inputs are present, even when a case wrapper already ran other CNV tools.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

wrapper_ran=0
if w="$(find_wrapper cnv_all || true)"; then
  bash "$w"
  wrapper_ran=1
elif w="$(find_wrapper cnv_hla_parallel || true)"; then
  RUN_CNV=1 RUN_HLA=0 bash "$w"
  wrapper_ran=1
fi

# Gold Sequenza path: skip if .fit.done; otherwise run skill/deps runner.
if [[ -n "${TUMOR_BAM:-}" && -n "${NORMAL_BAM:-}" ]] || find_wrapper sequenza_steps >/dev/null 2>&1; then
  bash "${SCRIPT_DIR}/stages/sequenza.sh" || {
    if [[ "${CONTINUE_ON_ERROR:-1}" == "1" ]]; then
      warn "Sequenza failed; CONTINUE_ON_ERROR=1"
    else
      die "SEQUENZA_FAILED" "Sequenza 失败。见 ${CASE_ROOT}/sequenza/run.log"
    fi
  }
elif [[ "$wrapper_ran" -eq 0 ]]; then
  die "NO_WRAPPER" "请提供 ${CASE_ROOT}/scripts/run_cnv_all.sh，或传 --tumor-bam/--normal-bam 以跑内置 Sequenza。"
fi

ok "CNV queue finished"
