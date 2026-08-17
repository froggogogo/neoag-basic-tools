#!/usr/bin/env bash
# Sequenza: sunbinbin gold path (NUL-safe bam2seqz + chrom-split fread fit).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

DONE="${CASE_ROOT}/sequenza/.fit.done"
SUMMARY="${CASE_ROOT}/sequenza/sequenza_fit/${SAMPLE_ID}.sequenza_summary.tsv"
if marker_done "$DONE" && [[ -s "$SUMMARY" ]]; then
  ok "Sequenza already done -> ${SUMMARY}"
  exit 0
fi

if [[ -z "${TUMOR_BAM:-}" || -z "${NORMAL_BAM:-}" ]]; then
  if w="$(find_wrapper sequenza_steps || true)"; then
    log "Sequenza via ${w} (no BAM args; wrapper must have them)"
    bash "$w"
    exit $?
  fi
  die "NEED_BAM" "Sequenza 需要 --tumor-bam 与 --normal-bam，或病例 scripts/run_sequenza_steps.sh"
fi

STEPS=""
for c in \
  "${DEPS_DIR}/tools/sequenza/run_sequenza_steps.sh" \
  "${SCRIPT_DIR}/tools/sequenza/run_sequenza_steps.sh" \
  "${SCRIPT_DIR}/../../scripts/tools/sequenza/run_sequenza_steps.sh"
do
  [[ -f "$c" ]] && STEPS="$c" && break
done
if [[ -z "$STEPS" ]]; then
  if w="$(find_wrapper sequenza_steps || true)"; then
    STEPS="$w"
  fi
fi
[[ -n "$STEPS" ]] || die "NO_SEQUENZA_RUNNER" "找不到 run_sequenza_steps.sh（安装 skill 应写入 \$DEPS_DIR/tools/sequenza/）"

export SAMPLE_ID TUMOR_BAM NORMAL_BAM DEPS_DIR
export OUTDIR="${CASE_ROOT}/sequenza"
export CASE_ROOT
if [[ "${SCHED_MODE:-serial}" == "serial" ]]; then
  export CHUNK_JOBS="${CHUNK_JOBS:-1}"
else
  export CHUNK_JOBS="${CHUNK_JOBS:-2}"
fi

log "Sequenza via ${STEPS} CHUNK_JOBS=${CHUNK_JOBS}"
SEQUENZA_STEP="${SEQUENZA_STEP:-all}" bash "$STEPS"
[[ -s "$SUMMARY" ]] || warn "Sequenza 结束但缺少 ${SUMMARY}"
ok "Sequenza finished"
