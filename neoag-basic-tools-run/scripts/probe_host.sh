#!/usr/bin/env bash
# Probe CPU/memory and choose serial | dual | full schedule.
# Dual/full match sunbinbin's CNV||HLA and RNA wave parallelism.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"

# Thresholds (sunbinbin ran CNV||HLA on ~20 threads / ~235G; leave headroom)
MIN_DUAL_NPROC="${MIN_DUAL_NPROC:-12}"
MIN_DUAL_MEM_GB="${MIN_DUAL_MEM_GB:-48}"
MIN_FULL_NPROC="${MIN_FULL_NPROC:-20}"
MIN_FULL_MEM_GB="${MIN_FULL_MEM_GB:-96}"

NPROC="$(host_nproc)"
MEM_GB="$(host_mem_gb)"
AVAIL_GB="$(host_avail_mem_gb)"
LOAD1="$(host_load1)"
OS="$( ( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" ) || echo unknown )"
EF=0
is_ubuntu_2204 && EF=1

MODE="serial"
REASON="nproc=${NPROC} mem_gb=${MEM_GB} below dual (${MIN_DUAL_NPROC}c/${MIN_DUAL_MEM_GB}G)"

if [[ "$NPROC" -ge "$MIN_FULL_NPROC" && "$MEM_GB" -ge "$MIN_FULL_MEM_GB" ]]; then
  MODE="full"
  REASON="nproc=${NPROC}>=${MIN_FULL_NPROC} and mem_gb=${MEM_GB}>=${MIN_FULL_MEM_GB}: DNA (CNV||HLA) ∥ RNA EasyFuse wave"
elif [[ "$NPROC" -ge "$MIN_DUAL_NPROC" && "$MEM_GB" -ge "$MIN_DUAL_MEM_GB" ]]; then
  MODE="dual"
  REASON="nproc=${NPROC}>=${MIN_DUAL_NPROC} and mem_gb=${MEM_GB}>=${MIN_DUAL_MEM_GB}: CNV||HLA; RNA after DNA HLA"
fi

if [[ "${1:-}" == "--json" ]]; then
  cat <<EOF
{
  "nproc": ${NPROC},
  "mem_gb": ${MEM_GB},
  "avail_mem_gb": ${AVAIL_GB},
  "load1": ${LOAD1},
  "mode": "${MODE}",
  "easyfuse_os": ${EF},
  "os": "$(printf '%s' "$OS" | sed 's/"/\\"/g')",
  "reason": "${REASON}",
  "thresholds": {
    "dual_nproc": ${MIN_DUAL_NPROC},
    "dual_mem_gb": ${MIN_DUAL_MEM_GB},
    "full_nproc": ${MIN_FULL_NPROC},
    "full_mem_gb": ${MIN_FULL_MEM_GB}
  }
}
EOF
  exit 0
fi

cat <<EOF
======== neoag-basic-tools-run host probe ========
os:            ${OS}
nproc:         ${NPROC}
mem_gb:        ${MEM_GB}
avail_mem_gb:  ${AVAIL_GB}
load1:         ${LOAD1}
easyfuse_os:   ${EF} (Ubuntu 22.04 only)
mode:          ${MODE}
reason:        ${REASON}
==================================================
serial = all basic tools one-by-one
dual   = CNV queue ∥ HLA queue; RNA after HLA
full   = (CNV ∥ HLA) ∥ RNA (Salmon→EasyFuse); SNAF/SpliceMutr wait HLA
EOF
