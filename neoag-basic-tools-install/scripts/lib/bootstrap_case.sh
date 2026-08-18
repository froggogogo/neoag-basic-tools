#!/usr/bin/env bash
# Source this from case wrappers (sunbinbin-style) instead of hardcoding
# /root/neo or /home/na/miniforge3.
#
#   source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/bootstrap_case.sh
#
# Order: portable site.env → optional neo conf/tools.env.sh → site.env again
# so tools.env cannot clobber DEPS refs / pVAC isolation.

_NEOAG_BOOTSTRAP_DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
export NEOAG_BASIC_DEPS_DIR="${_NEOAG_BOOTSTRAP_DEPS}"
export NEOAG_SITE_QUIET="${NEOAG_SITE_QUIET:-1}"

if [[ -f "${_NEOAG_BOOTSTRAP_DEPS}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${_NEOAG_BOOTSTRAP_DEPS}/configs/site.env.sh"
fi

if [[ -n "${NEOAG_ROOT:-}" && -f "${NEOAG_ROOT}/conf/tools.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${NEOAG_ROOT}/conf/tools.env.sh"
  [[ -f "${NEOAG_ROOT}/conf/tools.env.local.sh" ]] && source "${NEOAG_ROOT}/conf/tools.env.local.sh"
  if [[ -f "${_NEOAG_BOOTSTRAP_DEPS}/configs/site.env.sh" ]]; then
    # shellcheck disable=SC1090
    source "${_NEOAG_BOOTSTRAP_DEPS}/configs/site.env.sh"
  fi
fi

# sunbinbin inputs.env.sh historically set TF_USE_LEGACY_KERAS=1 which breaks
# neoag-pvactools711 MHCflurry. Always clear after case wrappers.
unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true

# Re-apply portable overlay last so 66-only defaults cannot clobber 134/169.
if [[ -f "${_NEOAG_BOOTSTRAP_DEPS}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${_NEOAG_BOOTSTRAP_DEPS}/configs/site.env.sh"
fi
unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true
