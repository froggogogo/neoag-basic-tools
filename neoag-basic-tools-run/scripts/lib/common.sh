#!/usr/bin/env bash
# Shared helpers for neoag-basic-tools-run
set -euo pipefail

NEOAG_RUN_VERSION="1.1.0"
DEFAULT_DEPS_DIR="/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps"

log()  { printf '[%s] INFO  %s\n'  "$(date '+%F %T')" "$*"; }
ok()   { printf '[%s] OK    %s\n'  "$(date '+%F %T')" "$*"; }
warn() { printf '[%s] WARN  %s\n'  "$(date '+%F %T')" "$*" >&2; }
err()  { printf '[%s] ERROR %s\n'  "$(date '+%F %T')" "$*" >&2; }

die() {
  local code="${1:-GENERIC}"
  shift || true
  err "reason=${code}"
  err "$*"
  exit 1
}

host_nproc() {
  nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
}

host_mem_gb() {
  awk '/MemTotal:/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0
}

host_avail_mem_gb() {
  awk '/MemAvailable:/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0
}

host_load1() {
  awk '{printf "%.0f", $1}' /proc/loadavg 2>/dev/null || echo 0
}

is_ubuntu_2204() {
  [[ -r /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "22.04" ]]
}

marker_done() {
  local f="$1"
  [[ "${FORCE:-0}" == "1" ]] && return 1
  [[ -f "$f" ]]
}

touch_done() {
  mkdir -p "$(dirname "$1")"
  date -Is > "$1"
}

wait_pids() {
  local fails=0 pid
  for pid in "$@"; do
    [[ -n "$pid" ]] || continue
    if ! wait "$pid"; then
      fails=$((fails + 1))
    fi
  done
  return "$fails"
}

ensure_case_layout() {
  local root="$1"
  mkdir -p \
    "${root}/logs" "${root}/tmp" "${root}/evidence" \
    "${root}/hla"/{optitype,spechla,hla_la} \
    "${root}/facets" "${root}/sequenza" "${root}/purple" "${root}/ascat" \
    "${root}/lohhla" \
    "${root}/short-rna"/{logs,tmp,evidence,salmon,star,star-fusion,arriba,regtools,easyfuse,snaf,splicemutr}
  export TMPDIR="${TMPDIR:-${root}/tmp}"
  export TMP="${TMP:-${TMPDIR}}"
  export TEMP="${TEMP:-${TMPDIR}}"
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Djava.io.tmpdir=${TMPDIR}}"
  export _JAVA_OPTIONS="${_JAVA_OPTIONS:--Djava.io.tmpdir=${TMPDIR}}"
}

export_case_env() {
  [[ -n "${CASE_ROOT:-}" ]] || return 0
  export PATIENT_ID="${PATIENT_ID:-${SAMPLE_ID}}"
  [[ -n "${TUMOR_BAM:-}" ]] && export TUMOR_BAM
  [[ -n "${NORMAL_BAM:-}" ]] && export NORMAL_BAM
  [[ -n "${SOMATIC_VCF:-}" ]] && export SOMATIC_VCF
  [[ -n "${RNA_R1:-}" ]] && export RNA_FASTQ1="${RNA_R1}" RNA_R1
  [[ -n "${RNA_R2:-}" ]] && export RNA_FASTQ2="${RNA_R2}" RNA_R2
  if [[ -f "${CASE_ROOT}/short-rna/inputs.env.sh" ]]; then
    # shellcheck disable=SC1090
    source "${CASE_ROOT}/short-rna/inputs.env.sh"
  elif [[ -f "${CASE_ROOT}/inputs.env.sh" ]]; then
    # shellcheck disable=SC1090
    source "${CASE_ROOT}/inputs.env.sh"
  fi
  # Restore portable conda/tools after case defaults (66-only paths, TF_USE_LEGACY_KERAS).
  if [[ -f "${DEPS_DIR:-}/configs/bootstrap_case.sh" ]]; then
    # shellcheck disable=SC1090
    source "${DEPS_DIR}/configs/bootstrap_case.sh"
  elif [[ -f "${DEPS_DIR:-}/configs/site.env.sh" ]]; then
    # shellcheck disable=SC1090
    source "${DEPS_DIR}/configs/site.env.sh"
  fi
  unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true
}
