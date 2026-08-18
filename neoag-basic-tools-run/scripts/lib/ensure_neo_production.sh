#!/usr/bin/env bash
# Overlay neo production interface: complete predictor paths + sarcoma immunogenicity.
# Called from stages/production.sh. Requires NEO_ROOT, DEPS_DIR.
set -euo pipefail

ensure_neo_tools_env_local() {
  local dest="${NEO_ROOT}/conf/tools.env.local.sh"
  local src="${RUN_SKILL_ROOT}/configs/tools.env.local.sh"
  [[ -f "$src" ]] || die "NO_PROD_OVERLAY" "缺少 ${src}"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    return 0
  fi
  if [[ -f "$dest" ]]; then
    cp -a "$dest" "${dest}.bak_$(date +%Y%m%d_%H%M%S)"
  fi
  cp -a "$src" "$dest"
  log "wrote ${dest} (BigMHC/DeepImmuno/MixMHCpred/PRIME/netChop overlay)"
}

ensure_neo_immunogenicity_profile() {
  local py="$1"
  local patcher="${RUN_SKILL_ROOT}/scripts/lib/patch_immunogenicity.py"
  [[ -f "$patcher" ]] || die "NO_IMMUNO_PATCH" "缺少 ${patcher}"
  "$py" "$patcher" --neo-root "$NEO_ROOT"
}

ensure_neo_production() {
  local py="${2:-python3}"
  RUN_SKILL_ROOT="${1:?run skill root}"
  [[ -n "${NEO_ROOT:-}" && -d "${NEO_ROOT}" ]] || die "NO_NEO_ROOT" "ensure_neo_production 需要 NEO_ROOT"
  ensure_neo_tools_env_local
  ensure_neo_immunogenicity_profile "$py"
}
