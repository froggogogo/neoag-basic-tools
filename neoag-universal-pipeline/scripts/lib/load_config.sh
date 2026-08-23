#!/usr/bin/env bash
# Load case.config.sh + portable site env (134 gold path).
# Usage: source "$(dirname "$0")/load_config.sh" /path/to/case.config.sh
set -euo pipefail

_CONFIG="${1:-${CASE_CONFIG:-}}"
if [[ -z "${_CONFIG}" ]]; then
  # Try CASE_ROOT/case.config.sh
  _CONFIG="${CASE_ROOT:-}/case.config.sh"
fi
[[ -f "${_CONFIG}" ]] || {
  echo "ERROR: case config not found: ${_CONFIG}" >&2
  echo "  Copy config/case.config.sh.template → \$CASE_ROOT/case.config.sh" >&2
  exit 1
}
# shellcheck disable=SC1090
source "${_CONFIG}"

DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
if [[ -f "${DEPS}/configs/bootstrap_case.sh" ]]; then
  # shellcheck disable=SC1091
  source "${DEPS}/configs/bootstrap_case.sh"
fi
unset TF_USE_LEGACY_KERAS KERAS_BACKEND 2>/dev/null || true

: "${PATIENT_ID:?PATIENT_ID required in case.config.sh}"
: "${TUMOR_BAM:?TUMOR_BAM required}"
: "${NORMAL_BAM:?NORMAL_BAM required}"
: "${CASE_ROOT:?CASE_ROOT required}"

mkdir -p "${CASE_ROOT}/tmp" "${CASE_ROOT}/logs"
export TMPDIR="${TMPDIR:-${CASE_ROOT}/tmp}"
export LOG_DIR="${LOG_DIR:-${CASE_ROOT}/logs}"

echo "[load_config] PATIENT_ID=${PATIENT_ID} CASE_ROOT=${CASE_ROOT}"
echo "[load_config] NEOAG_ROOT=${NEOAG_ROOT:-?} CONDA=${NEOAG_CONDA_BASE:-?}"
