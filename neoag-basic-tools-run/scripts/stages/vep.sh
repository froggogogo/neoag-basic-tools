#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

if [[ -z "${SOMATIC_VCF:-}" ]]; then
  warn "未给 --somatic-vcf，跳过 VEP"
  exit 0
fi
if w="$(find_wrapper vep_somatic || true)"; then
  if [[ -f "${DEPS_DIR}/configs/site.env.sh" ]]; then
    # shellcheck disable=SC1090
    source "${DEPS_DIR}/configs/site.env.sh"
    type neoag_use_vep_perl >/dev/null 2>&1 && neoag_use_vep_perl || true
  fi
  bash "$w"
else
  warn "无 run_vep_somatic.sh，跳过 VEP（生产可复用已 CSQ 的 VCF）"
fi
ok "VEP stage finished"
