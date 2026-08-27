#!/usr/bin/env bash
# =============================================================================
# sunbinbin NeoAg sliding-window SNV/InDel (VEP peptides + NetMHCpan/MHCflurry + rank)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_ROOT="${CASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
# Portable env (66/134/169): resolve NEOAG_ROOT without hardcoding 134 paths
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_portable_env.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_site_defaults.sh"
resolve_ref_fasta

PATIENT_ID="${PATIENT_ID:?export PATIENT_ID}"
TUMOR_SAMPLE="${TUMOR_SAMPLE_ID:-${PATIENT_ID}_tumor}"
HLA_FILE="${HLA_FILE:-${CASE_ROOT}/hla/hla_consensus.txt}"
# Prefer VEP-annotated VCF if ready; else PASS somatic
VEP_VCF="${VEP_VCF:-${CASE_ROOT}/vep/${PATIENT_ID}_tumor.somatic.vep.vcf}"
SOMATIC_VCF="${SOMATIC_VCF:-${CASE_ROOT}/somatic/${PATIENT_ID}_tumor.somatic.pass.vcf.gz}"
if [[ -s "${VEP_VCF}" ]]; then
  VARIANTS_VCF="${VARIANTS_VCF:-${VEP_VCF}}"
elif [[ -s "${SOMATIC_VCF}" ]]; then
  VARIANTS_VCF="${VARIANTS_VCF:-${SOMATIC_VCF}}"
else
  VARIANTS_VCF="${VARIANTS_VCF:?export VARIANTS_VCF or provide VEP_VCF/SOMATIC_VCF}"
fi
OUT="${OUTDIR:-${CASE_ROOT}/sliding}"
LOG="${LOG:-${OUT}/run.sliding.log}"
FORCE="${FORCE:-0}"
TOOLS_STUB="${TOOLS_STUB:-0}"
export TMPDIR="${TMPDIR:-${CASE_ROOT}/tmp/sliding}"
export TMP="${TMP:-${TMPDIR}}"
export TEMP="${TEMP:-${TMPDIR}}"
# export ref for neoag
export NEOAG_REFERENCE_FASTA="${REF_FASTA:-${NEOAG_REFERENCE_FASTA:-}}"
# Avoid TF legacy/keras pollution from broader conda sessions (breaks MHCflurry)
unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true
# Prefer MHCflurry from pvactools711 (compatible with its tf/keras stack)
_PVAC_BIN="${NEOAG_PVAC_ENV:-${PVAC_ENV:-${NEOAG_CONDA_BASE:-}/envs/neoag-pvactools711}}/bin"
if [[ -x "${_PVAC_BIN}/mhcflurry-predict" ]]; then
  export PATH="${_PVAC_BIN}:${PATH}"
fi
unset _PVAC_BIN
# NetMHCpan tree is on neoag_100T. Binary INTERP points at neoag-tools sysroot, so
# docker must bind-mount that conda prefix (not /root/neo/licensed_tools or zjl).
export NETMHCPAN_HOME="${NETMHCPAN_HOME:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/licenses/predictors/netMHCpan}"
export NEOAG_NETMHCPAN_BIN="${NEOAG_NETMHCPAN_BIN:-${NETMHCPAN_HOME}/netMHCpan}"
export NEOAG_NETMHCPAN_ENGINE="${NEOAG_NETMHCPAN_ENGINE:-docker}"
export NEOAG_NETMHCPAN_TMPDIR="${NEOAG_NETMHCPAN_TMPDIR:-${CASE_ROOT}/tmp/netmhcpan}"
_conda="${NEOAG_CONDA_BASE:-${CONDA_BASE:-/root/neo/envs/miniforge3}}"
export NEOAG_NETMHCPAN_EXTRA_MOUNTS="${NEOAG_NETMHCPAN_EXTRA_MOUNTS:-/mnt/neoag_100T:/mnt/neoag_100T:ro,${_conda}:${_conda}:ro,/mnt/zzbnew:/mnt/zzbnew:rw}"
mkdir -p "${NEOAG_NETMHCPAN_TMPDIR}"

mkdir -p "${OUT}" "${TMPDIR}"
exec > >(tee -a "${LOG}") 2>&1

echo "==> sliding_sunbinbin $(date -Is)"
echo "    vcf=${VARIANTS_VCF}"
echo "    tumor_sample=${TUMOR_SAMPLE}"
echo "    hla=${HLA_FILE}"
echo "    out=${OUT}"
echo "    neoag_root=${NEOAG_ROOT}"

[[ -s "${VARIANTS_VCF}" ]] || { echo "ERROR: variants VCF missing" >&2; exit 1; }
[[ -s "${HLA_FILE}" ]] || { echo "ERROR: HLA file missing" >&2; exit 1; }

RANKED="${OUT}/run-full/scoring/ranked_peptides.tsv"
if [[ -s "${RANKED}" && "${FORCE}" != "1" ]]; then
  echo "==> sliding already complete: ${RANKED}"
  date -Is > "${OUT}/.sliding.done"
  exit 0
fi

export PYTHONPATH="${NEOAG_ROOT}/src${PYTHONPATH:+:${PYTHONPATH}}"
cd "${NEOAG_ROOT}"

# Avoid empty-arg expansion ("") which argparse rejects as unrecognized
cmd=(
  python3 -m neoag.agent_skills.sliding_run
  --project-root "${NEOAG_ROOT}"
  --variants-vcf "${VARIANTS_VCF}"
  --hla "${HLA_FILE}"
  --outdir "${OUT}"
  --sample-id "${PATIENT_ID}"
  --tumor-sample-name "${TUMOR_SAMPLE}"
)
if [[ "${TOOLS_STUB}" == "1" ]]; then
  cmd+=(--tools-stub --immunogenicity-stub)
fi
"${cmd[@]}"

# sliding_run returns via exit code of run-full
if [[ ! -s "${RANKED}" ]]; then
  echo "ERROR: ranked_peptides.tsv missing after sliding run" >&2
  echo "    see ${OUT}/run-full.log" >&2
  exit 1
fi

mkdir -p "${CASE_ROOT}/evidence"
cp -f "${RANKED}" "${CASE_ROOT}/evidence/sliding_ranked_peptides.tsv" || true
cp -f "${OUT}/run-full/scoring/ranked_events.tsv" "${CASE_ROOT}/evidence/sliding_ranked_events.tsv" 2>/dev/null || true
ln -sfn "${OUT}/run-full" "${CASE_ROOT}/evidence/sliding_run" || true
date -Is > "${OUT}/.sliding.done"
echo "==> sliding done $(date -Is)"
ls -la "${RANKED}" "${OUT}/sliding_run_summary.json" 2>/dev/null || true
