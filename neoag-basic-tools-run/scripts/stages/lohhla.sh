#!/usr/bin/env bash
# LOHHLA after HLA consensus + purity.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

if marker_done "${CASE_ROOT}/lohhla/.lohhla.done"; then
  ok "LOHHLA already done"
  exit 0
fi
if w="$(find_wrapper lohhla || true)"; then
  bash "$w"
else
  warn "无 run_lohhla.sh，跳过 LOHHLA（生产仍可用其它 LOH 表）"
  exit 0
fi
ok "LOHHLA finished"
