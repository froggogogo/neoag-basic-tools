# Overlay for neo conf/tools.env.sh.
# Prefer install-deps complete predictors; fall back to liup/neodata4git.
# Copied onto $NEO_ROOT/conf/tools.env.local.sh by ensure_neo_production.sh.

_NEOAG_PRED_DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/licenses/predictors"
_NEOAG_PRED_LIUP="${NEOAG_PRED_FALLBACK:-/mnt/zzbnew/peixunban/gl/liup/neodata4git/data/predictors}"

_neoag_pick() {
  local sentinel="$1"
  local cand
  shift
  for cand in "$@"; do
    if [[ -n "${cand}" && -e "${cand}${sentinel}" ]]; then
      printf '%s' "${cand}"
      return 0
    fi
  done
  return 1
}

export NEOAG_TOOL_QUARANTINE="${_NEOAG_PRED_DEPS}"

_bigmhc="$(_neoag_pick "/src/predict.py" "${_NEOAG_PRED_DEPS}/bigmhc" "${_NEOAG_PRED_LIUP}/bigmhc" || true)"
export BIGMHC_DIR="${_bigmhc:-${_NEOAG_PRED_DEPS}/bigmhc}"

_deep="$(_neoag_pick "/deepimmuno-cnn.py" "${_NEOAG_PRED_DEPS}/DeepImmuno" "${_NEOAG_PRED_LIUP}/DeepImmuno" || true)"
export DEEPIMMUNO_DIR="${_deep:-${_NEOAG_PRED_DEPS}/DeepImmuno}"

_prime="$(_neoag_pick "/PRIME" "${_NEOAG_PRED_DEPS}/prime" "${_NEOAG_PRED_LIUP}/prime" || true)"
export PRIME_HOME="${_prime:-${_NEOAG_PRED_DEPS}/prime}"

_mix="$(_neoag_pick "/MixMHCpred" "${_NEOAG_PRED_DEPS}/mixMHCpred_install" "${_NEOAG_PRED_LIUP}/mixMHCpred_install" || true)"
export MIXMHCPRED_HOME="${_mix:-${_NEOAG_PRED_DEPS}/mixMHCpred_install}"

_netchop_home="$(_neoag_pick "/Linux_x86_64/bin/netChop" \
  "${_NEOAG_PRED_DEPS}/netchop/netchop-3.1" \
  "${_NEOAG_PRED_LIUP}/netchop/netchop-3.1" || true)"
export NETCHOP_HOME="${_netchop_home:-${_NEOAG_PRED_LIUP}/netchop/netchop-3.1}"
export NETCHOP="${NETCHOP_HOME}/Linux_x86_64"
export NEOAG_NETCHOP_BIN="${NETCHOP}/bin/netChop"
export NETCHOP_BIN="${NEOAG_NETCHOP_BIN}"

if [[ -n "${NEOAG_CONDA_BASE:-}" ]]; then
  export BIGMHC_PYTHON="${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python"
  export NEOAG_PRIME_PYTHON="${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python"
fi
export NEOAG_PRIME_BIN="${PRIME_HOME}/PRIME"
export MIXMHCPRED_BIN="${MIXMHCPRED_HOME}/MixMHCpred"
export PATH="${PRIME_HOME}:${MIXMHCPRED_HOME}:${NETCHOP}/bin:${PATH:-}"

unset _bigmhc _deep _prime _mix _netchop_home
unset -f _neoag_pick
unset _NEOAG_PRED_DEPS _NEOAG_PRED_LIUP
