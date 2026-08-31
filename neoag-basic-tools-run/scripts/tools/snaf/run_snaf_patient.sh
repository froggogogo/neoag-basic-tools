#!/usr/bin/env bash
# Case-aware SNAF launcher for neoag-basic-tools-run.
# Single STAR BAM, optional SJ.out.tab gate, genomic start<=end. No fake replicate.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE="${_SCRIPT_DIR}/run_snaf_pipeline.sh"

CASE_ROOT="${CASE_ROOT:?ERROR: CASE_ROOT is required}"
SAMPLE_ID="${SAMPLE_ID:?ERROR: SAMPLE_ID is required}"
DEPS_DIR="${DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"

BAM="${BAM:-${CASE_ROOT}/short-rna/star/Aligned.sortedByCoord.out.bam}"
STAR_SJ="${STAR_SJ:-${CASE_ROOT}/short-rna/star/SJ.out.tab}"
HLA="${HLA:-${CASE_ROOT}/hla/hla_consensus.txt}"
OUT="${OUT:-${CASE_ROOT}/short-rna/snaf}"
THREADS="${THREADS:-${NEOAG_SNAF_CORES:-8}}"

SNAF_DB="${NEOAG_SNAF_DB:-}"
if [[ -z "$SNAF_DB" ]]; then
  for cand in \
    "${DEPS_DIR}/refs/snaf/reference/data" \
    "${DEPS_DIR}/refs/snaf"
  do
    if [[ -s "${cand}/controls/GTEx_junction_counts.h5ad" ]]; then
      SNAF_DB="$cand"
      break
    fi
  done
fi
[[ -n "$SNAF_DB" ]] || { echo "ERROR: SNAF database not found (set NEOAG_SNAF_DB)" >&2; exit 2; }

if [[ -z "${SNAF_PYTHON:-}" ]]; then
  for py in \
    "${DEPS_DIR}/software/miniforge3/envs/neoag-snaf/bin/python" \
    "${NEOAG_CONDA_BASE:-}/envs/neoag-snaf/bin/python"
  do
    if [[ -x "$py" ]]; then
      export SNAF_PYTHON="$py"
      break
    fi
  done
fi

export NEOAG_ALTANALYZE_IMAGE="${NEOAG_ALTANALYZE_IMAGE:-frankligy123/altanalyze:0.7.0.1}"
export NEOAG_SNAF_FORCE_REBIND="${NEOAG_SNAF_FORCE_REBIND:-1}"
export SKIP_ALTANALYZE="${SKIP_ALTANALYZE:-0}"
# Prefer NetMHCpan (sunbinbin gold). MHCflurry often lacks models/PATH on intranet hosts.
if [[ -z "${NEOAG_NETMHCPAN_BIN:-}" ]]; then
  for cand in \
    "${CASE_ROOT}/short-rna/snaf/tools/netMHCpan-local" \
    "${CASE_ROOT}/production_from_results_manifest_"*/tools/netMHCpan-local \
    "/mnt/zzbnew/peixunban/gl/liup/neodata4git/data/predictors/netMHCpan/netMHCpan"
  do
    # shellcheck disable=SC2086
    for f in ${cand}; do
      if [[ -x "$f" ]]; then
        export NEOAG_NETMHCPAN_BIN="$f"
        break 2
      fi
    done
  done
fi
export NEOAG_SNAF_BINDING_METHOD="${NEOAG_SNAF_BINDING_METHOD:-netMHCpan}"
export NETMHCPAN_HOME="${NETMHCPAN_HOME:-/mnt/zzbnew/peixunban/gl/liup/neodata4git/data/predictors/netMHCpan}"

args=(
  --bam "$BAM"
  --hla-file "$HLA"
  --sample-id "$SAMPLE_ID"
  --db-dir "$SNAF_DB"
  --outdir "$OUT"
  --threads "$THREADS"
  --altanalyze-image "$NEOAG_ALTANALYZE_IMAGE"
)
[[ -s "$STAR_SJ" ]] && args+=(--star-sj "$STAR_SJ")

echo "==> SNAF gold pipeline sample=${SAMPLE_ID} bam=${BAM} db=${SNAF_DB} out=${OUT}"
bash "$PIPELINE" "${args[@]}"
