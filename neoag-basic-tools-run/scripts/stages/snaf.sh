#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

# Gold pipeline (no fake replicate; STAR SJ gate; BAM symlink provenance):
#   scripts/tools/snaf/run_snaf_pipeline.sh
# Case wrappers must not mount the same BAM as sample + sample_replicate.
if marker_done "${CASE_ROOT}/short-rna/snaf/.snaf.done"; then
  ok "SNAF already done"
  exit 0
fi
if w="$(find_wrapper snaf || true)"; then
  bash "$w"
else
  warn "无 SNAF wrapper，跳过（SpliceMutr 需要 SNAF 文本表）"
  exit 0
fi
ok "SNAF finished"
