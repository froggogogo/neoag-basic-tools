#!/usr/bin/env bash
# =============================================================================
# LOHHLA (HLA-LOH) — portable wrapper for 66 / 134 / 169
#
# Uses existing HLA consensus (skip Polysolver WGS typing when winners can be
# derived from HLA_FILE). Paths resolve via lib_portable_env + site.env
# (neoag_100T deps). No hardcoded /home/na 134 paths.
#
# Usage:
#   PATIENT_ID=... TUMOR_BAM=... NORMAL_BAM=... bash scripts/run_lohhla.sh
#   LOHHLA_STEP=polysolver|fasta|lohhla|all bash scripts/run_lohhla.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_ROOT="${CASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_portable_env.sh"

DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
CONDA_BASE="${NEOAG_CONDA_BASE:-}"

PATIENT_ID="${PATIENT_ID:?export PATIENT_ID}"
TUMOR_BAM="${TUMOR_BAM:?export TUMOR_BAM}"
NORMAL_BAM="${NORMAL_BAM:?export NORMAL_BAM}"
HLA_FILE="${HLA_FILE:-${CASE_ROOT}/hla/hla_consensus.txt}"
OUTDIR="${OUTDIR:-${CASE_ROOT}/lohhla}"
LOHHLA_NAS_ROOT="${LOHHLA_NAS_ROOT:-${CASE_ROOT}/lohhla/work}"
LOHHLA_OUT="${LOHHLA_OUT:-${LOHHLA_NAS_ROOT}/lohhla}"
LOHHLA_STEP="${LOHHLA_STEP:-all}"
COPYNUM_LOC="${COPYNUM_LOC:-${CASE_ROOT}/lohhla/copyNumSolutions.txt}"
LOG_DIR="${LOG_DIR:-${CASE_ROOT}/logs}"
LOG="${LOG:-${LOG_DIR}/lohhla_$(date +%Y%m%d_%H%M%S).log}"
LOHHLA_GATK_DIR="${LOHHLA_GATK_DIR:-${CASE_ROOT}/tmp/lohhla_gatk}"

_pick_dir() {
  local c
  for c in "$@"; do
    [[ -n "${c}" && -f "${c}/LOHHLAscript.R" ]] || continue
    echo "${c}"
    return 0
  done
  return 1
}

_pick_file() {
  local c
  for c in "$@"; do
    [[ -n "${c}" && -s "${c}" ]] || continue
    echo "${c}"
    return 0
  done
  return 1
}

# Prefer site.env exports; fall back to deps / shared NAS (not 134-only /home/na).
if [[ -z "${LOHHLA_HOME:-}" || ! -f "${LOHHLA_HOME}/LOHHLAscript.R" ]]; then
  LOHHLA_HOME="$(_pick_dir \
    "${LOHHLA_HOME:-}" \
    "${DEPS}/tools/lohhla" \
    "${DEPS}/tools/neodata_tools/LOHHLA" \
    "/mnt/zzbnew/peixunban/gl/liup/neodata4git/data/tools/lohhla" \
    "/mnt/zjl-bgi-zzb/peixunban/gl/liup/neodata4git/data/tools/lohhla" \
  )" || true
fi
export LOHHLA_HOME="${LOHHLA_HOME:?ERROR: LOHHLA_HOME not found (need LOHHLAscript.R under deps/tools/lohhla)}"

if [[ -z "${POLYSOLVER_HOME:-}" || ! -d "${POLYSOLVER_HOME}/data" ]]; then
  POLYSOLVER_HOME="${DEPS}/refs/lohhla/polysolver"
fi
export POLYSOLVER_HOME
[[ -d "${POLYSOLVER_HOME}/data/complete" ]] || {
  echo "ERROR: Polysolver data missing: ${POLYSOLVER_HOME}/data/complete" >&2
  exit 1
}

if [[ -z "${NOVOALIGN_LICENSE_FILE:-}" || ! -s "${NOVOALIGN_LICENSE_FILE}" ]]; then
  NOVOALIGN_LICENSE_FILE="$(_pick_file \
    "${NOVOALIGN_LICENSE_FILE:-}" \
    "${DEPS}/refs/lohhla/novoalign.lic" \
  )" || true
fi
export NOVOALIGN_LICENSE_FILE="${NOVOALIGN_LICENSE_FILE:?ERROR: novoalign.lic missing under deps/refs/lohhla/}"

mkdir -p "${OUTDIR}" "${LOHHLA_NAS_ROOT}" "${LOHHLA_OUT}" "${LOG_DIR}" "${LOHHLA_GATK_DIR}"
export LOHHLA_GATK_DIR

if [[ ! -f "${LOHHLA_GATK_DIR}/picard.jar" ]]; then
  PICARD_CAND=""
  for cand in \
    ${CONDA_BASE:+"${CONDA_BASE}/envs/neoag-gatk/share/picard-"*/picard.jar} \
    "/home/na/miniforge3/envs/neoag-gatk/share/picard-"*/picard.jar \
    "/root/neo/envs/miniforge3/envs/neoag-gatk/share/picard-"*/picard.jar \
    "${DEPS}/tools/picard/picard.jar" \
    "${DEPS}/tools/neodata_tools/conda_pkgs/picard-"*/picard.jar \
    "${DEPS}/tools/neodata_tools/HLA-LA/.conda/share/picard-"*/picard.jar
  do
    # shellcheck disable=SC2086
    for f in ${cand}; do
      if [[ -f "$f" ]]; then PICARD_CAND="$f"; break 2; fi
    done
  done
  [[ -n "${PICARD_CAND}" ]] || { echo "ERROR: picard.jar not found (neoag-gatk env)" >&2; exit 1; }
  ln -sfn "${PICARD_CAND}" "${LOHHLA_GATK_DIR}/picard.jar"
fi

[[ -s "${HLA_FILE}" ]] || { echo "ERROR: missing HLA_FILE ${HLA_FILE}" >&2; exit 1; }
[[ -s "${COPYNUM_LOC}" ]] || { echo "ERROR: missing COPYNUM_LOC ${COPYNUM_LOC}" >&2; exit 1; }

echo "==> LOHHLA launcher $(date -Is)"
echo "    PATIENT_ID=${PATIENT_ID}"
echo "    HLA_FILE=${HLA_FILE}"
echo "    COPYNUM_LOC=${COPYNUM_LOC}"
echo "    OUTDIR=${OUTDIR}"
echo "    LOHHLA_OUT=${LOHHLA_OUT}"
echo "    LOHHLA_STEP=${LOHHLA_STEP}"
echo "    LOHHLA_HOME=${LOHHLA_HOME}"
echo "    POLYSOLVER_HOME=${POLYSOLVER_HOME}"
echo "    NOVOALIGN_LICENSE_FILE=${NOVOALIGN_LICENSE_FILE}"
echo "    LOG=${LOG}"

# Resolve Polysolver allele IDs that lack an exact _01 3-field entry (e.g. B*27:05 -> _02).
resolve_winners_against_polysolver() {
  local winners="$1"
  local complete="${POLYSOLVER_HOME}/data/complete"
  local abc="${POLYSOLVER_HOME}/data/abc_complete.fasta"
  [[ -f "${winners}" ]] || return 0
  python3 - "${winners}" "${complete}" "${abc}" <<'PY'
import sys
from pathlib import Path
winners, complete, abc = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
headers = set()
if Path(abc).is_file():
    for line in Path(abc).open():
        if line.startswith(">"):
            headers.add(line[1:].strip().split()[0])
rows = []
n_changed = 0
def resolve(aid: str) -> str:
    global n_changed
    if (complete / f"{aid}.fasta").is_file() or aid in headers:
        return aid
    matches = sorted(complete.glob(f"{aid}*.fasta"))
    if matches:
        n_changed += 1
        return matches[0].stem
    parts = aid.split("_")
    if len(parts) >= 4:
        stem = "_".join(parts[:-1])
        matches = sorted(complete.glob(f"{stem}_*.fasta"))
        if matches:
            n_changed += 1
            return matches[0].stem
        if f"{stem}_02" in headers:
            n_changed += 1
            return f"{stem}_02"
    return aid
for line in winners.read_text().splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    if len(parts) < 3:
        rows.append(line)
        continue
    locus, a1, a2 = parts[0], parts[1], parts[2]
    rows.append(f"{locus}\t{resolve(a1)}\t{resolve(a2)}")
winners.write_text("\n".join(rows) + "\n")
print("winners resolved; n_changed=", n_changed)
for r in rows:
    print(r)
PY
}

# Re-assert portable paths AFTER tools.env* (they can override empties / wrong defaults).
export LOHHLA_HOME POLYSOLVER_HOME NOVOALIGN_LICENSE_FILE LOHHLA_GATK_DIR
export USE_HLA_FILE_FOR_WINNERS=1

run_step() {
  local step="$1"
  PATIENT_ID="${PATIENT_ID}" \
  TUMOR_BAM="${TUMOR_BAM}" \
  NORMAL_BAM="${NORMAL_BAM}" \
  HLA_FILE="${HLA_FILE}" \
  OUTDIR="${OUTDIR}" \
  LOHHLA_NAS_ROOT="${LOHHLA_NAS_ROOT}" \
  LOHHLA_OUT="${LOHHLA_OUT}" \
  LOHHLA_STEP="${step}" \
  COPYNUM_LOC="${COPYNUM_LOC}" \
  LOG="${LOG}" \
  LOHHLA_HOME="${LOHHLA_HOME}" \
  LOHHLA_GATK_DIR="${LOHHLA_GATK_DIR}" \
  POLYSOLVER_HOME="${POLYSOLVER_HOME}" \
  NOVOALIGN_LICENSE_FILE="${NOVOALIGN_LICENSE_FILE}" \
  USE_HLA_FILE_FOR_WINNERS="${USE_HLA_FILE_FOR_WINNERS}" \
  LOHHLA_MAPPING_STEP="${LOHHLA_MAPPING_STEP:-TRUE}" \
  LOHHLA_FISHING_STEP="${LOHHLA_FISHING_STEP:-TRUE}" \
  bash "${NEOAG_ROOT}/scripts/run_lohhla_sample.sh"
}

case "${LOHHLA_STEP}" in
  all)
    run_step polysolver
    resolve_winners_against_polysolver "${OUTDIR}/polysolver/winners.hla.txt"
    run_step fasta
    run_step lohhla
    ;;
  polysolver)
    run_step polysolver
    resolve_winners_against_polysolver "${OUTDIR}/polysolver/winners.hla.txt"
    ;;
  fasta)
    [[ -s "${OUTDIR}/polysolver/winners.hla.txt" ]] || run_step polysolver
    resolve_winners_against_polysolver "${OUTDIR}/polysolver/winners.hla.txt"
    run_step fasta
    ;;
  lohhla)
    run_step lohhla
    ;;
  *)
    echo "ERROR: LOHHLA_STEP must be all|polysolver|fasta|lohhla" >&2
    exit 2
    ;;
esac

PRED="$(find "${LOHHLA_OUT}" -name '*HLAlossPrediction_CI*' -type f 2>/dev/null | head -1 || true)"
if [[ -n "${PRED}" ]]; then
  echo "==> neoag convert-lohhla <- ${PRED}"
  PYTHONPATH="${NEOAG_ROOT}/src${PYTHONPATH:+:${PYTHONPATH}}" \
    python3 -m neoag.cli convert-lohhla -i "${PRED}" -o "${CASE_ROOT}/evidence/hla_loh.tsv" || \
    neoag convert-lohhla -i "${PRED}" -o "${CASE_ROOT}/evidence/hla_loh.tsv" || true
  date -Is > "${OUTDIR}/.lohhla.done"
else
  echo "WARN: HLAlossPrediction_CI not found under ${LOHHLA_OUT}; skip convert"
fi

echo "==> LOHHLA launcher finished $(date -Is)"
