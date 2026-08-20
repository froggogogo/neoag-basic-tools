#!/usr/bin/env bash
# Host-agnostic env for case wrappers (66 / 134 / 169).
# Source after SCRIPT_DIR is set. Does not override CASE_ROOT if already exported.
#
# Replaces hardcoded:
#   NEOAG_ROOT=/home/na/project/neoantigen/neoag_event_pipeline_v03_rc
#   source $NEOAG_ROOT/conf/tools.env.sh

_NEOAG_PORTABLE_DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
export NEOAG_BASIC_DEPS_DIR="${_NEOAG_PORTABLE_DEPS}"
export DEPS_DIR="${DEPS_DIR:-${_NEOAG_PORTABLE_DEPS}}"
export NEOAG_SITE_QUIET="${NEOAG_SITE_QUIET:-1}"

if [[ -z "${CASE_ROOT:-}" && -n "${SCRIPT_DIR:-}" ]]; then
  CASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi
export CASE_ROOT="${CASE_ROOT:-}"

if [[ -f "${_NEOAG_PORTABLE_DEPS}/configs/bootstrap_case.sh" ]]; then
  # shellcheck disable=SC1090
  source "${_NEOAG_PORTABLE_DEPS}/configs/bootstrap_case.sh"
elif [[ -f "${_NEOAG_PORTABLE_DEPS}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${_NEOAG_PORTABLE_DEPS}/configs/site.env.sh"
fi

_neoag_try_root() {
  local c="$1"
  [[ -n "$c" && -f "${c}/conf/tools.env.sh" ]] || return 1
  export NEOAG_ROOT="$c"
  # shellcheck disable=SC1090
  source "${c}/conf/tools.env.sh"
  [[ -f "${c}/conf/tools.env.local.sh" ]] && source "${c}/conf/tools.env.local.sh"
  if [[ -f "${_NEOAG_PORTABLE_DEPS}/configs/site.env.sh" ]]; then
    # shellcheck disable=SC1090
    source "${_NEOAG_PORTABLE_DEPS}/configs/site.env.sh"
  fi
  unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true
  return 0
}

if [[ -z "${NEOAG_ROOT:-}" || ! -f "${NEOAG_ROOT}/conf/tools.env.sh" ]]; then
  _picked=0
  for _c in \
    "${NEOAG_ROOT:-}" \
    "/root/neo/src/na0707_upload_release" \
    "/home/na/project/neoantigen/neoag_event_pipeline_na0707_sync_20260811" \
    "/home/na/project/neoantigen/neoag_event_pipeline_v03_rc" \
    "${_NEOAG_PORTABLE_DEPS}/src/neo"
  do
    if _neoag_try_root "${_c}"; then
      _picked=1
      break
    fi
  done
  if [[ "${_picked}" -ne 1 ]]; then
    echo "ERROR: cannot resolve NEOAG_ROOT with conf/tools.env.sh on this host" >&2
    echo "  Set NEOAG_ROOT to a neo checkout (66: /root/neo/src/na0707_upload_release)." >&2
    return 1 2>/dev/null || exit 1
  fi
  unset _picked _c
fi

unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true
echo "[portable_env] NEOAG_ROOT=${NEOAG_ROOT} CASE_ROOT=${CASE_ROOT:-?} CONDA_BASE=${NEOAG_CONDA_BASE:-?}"
