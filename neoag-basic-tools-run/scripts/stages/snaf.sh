#!/usr/bin/env bash
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
if w="$(find_wrapper snaf || true)"; then
  bash "$w"
else
  warn "无 SNAF wrapper，跳过（SpliceMutr 需要 SNAF 文本表）"
  exit 0
fi
ok "SNAF finished"
