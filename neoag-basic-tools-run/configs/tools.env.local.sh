# Overlay for neo conf/tools.env.sh when the *run skill* executes.
# Skill-side predictors live only under $DEPS_DIR (neoag_100T). No other NAS.

_NEOAG_PRED_DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/licenses/predictors"

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

_bigmhc="$(_neoag_pick "/src/predict.py" "${_NEOAG_PRED_DEPS}/bigmhc" || true)"
export BIGMHC_DIR="${_bigmhc:-${_NEOAG_PRED_DEPS}/bigmhc}"

_deep="$(_neoag_pick "/deepimmuno-cnn.py" "${_NEOAG_PRED_DEPS}/DeepImmuno" || true)"
export DEEPIMMUNO_DIR="${_deep:-${_NEOAG_PRED_DEPS}/DeepImmuno}"

_prime="$(_neoag_pick "/PRIME" "${_NEOAG_PRED_DEPS}/prime" || true)"
export PRIME_HOME="${_prime:-${_NEOAG_PRED_DEPS}/prime}"

_mix="$(_neoag_pick "/MixMHCpred" "${_NEOAG_PRED_DEPS}/mixMHCpred_install" || true)"
export MIXMHCPRED_HOME="${_mix:-${_NEOAG_PRED_DEPS}/mixMHCpred_install}"

_netchop_home="$(_neoag_pick "/Linux_x86_64/bin/netChop" \
  "${_NEOAG_PRED_DEPS}/netchop/netchop-3.1" || true)"
export NETCHOP_HOME="${_netchop_home:-${_NEOAG_PRED_DEPS}/netchop/netchop-3.1}"
export NETCHOP="${NETCHOP_HOME}/Linux_x86_64"
export NEOAG_NETCHOP_BIN="${NETCHOP}/bin/netChop"
export NETCHOP_BIN="${NEOAG_NETCHOP_BIN}"

_stab="$(_neoag_pick "/Linux_x86_64/bin/netMHCstabpan" \
  "${_NEOAG_PRED_DEPS}/netMHCstabpan" || true)"
export NETMHCSTABPAN_HOME="${_stab:-${_NEOAG_PRED_DEPS}/netMHCstabpan}"
export NETMHCSTABPAN_BIN="${NETMHCSTABPAN_HOME}/netMHCstabpan"
export PATH="${NETMHCSTABPAN_HOME}:${PATH:-}"

if [[ -n "${NEOAG_CONDA_BASE:-}" ]]; then
  export BIGMHC_PYTHON="${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python"
  export NEOAG_PRIME_PYTHON="${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python"
fi
export NEOAG_PRIME_BIN="${PRIME_HOME}/PRIME"
export MIXMHCPRED_BIN="${MIXMHCPRED_HOME}/MixMHCpred"
export PATH="${PRIME_HOME}:${MIXMHCPRED_HOME}:${NETCHOP}/bin:${PATH:-}"

unset _bigmhc _deep _prime _mix _netchop_home _stab
unset -f _neoag_pick
unset _NEOAG_PRED_DEPS
