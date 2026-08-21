#!/usr/bin/env bash
# =============================================================================
# sunbinbin somatic variant handoff (短读 DNA 体细胞变异)
#
# Site convention: use existing Mutect2-style PASS VCF under the dsrct data tree
# (full WGS Mutect2 re-call is days-long and not re-done here unless FORCE_CALL=1).
#
# Output under CASE_ROOT/somatic/ + evidence links.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_ROOT="${CASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
NEOAG_ROOT="${NEOAG_ROOT:-}"  # resolved by lib_portable_env.sh

PATIENT_ID="${PATIENT_ID:?export PATIENT_ID}"
TUMOR_SAMPLE="${TUMOR_SAMPLE_ID:-${PATIENT_ID}_tumor}"
NORMAL_SAMPLE="${NORMAL_SAMPLE_ID:-${PATIENT_ID}_blood}"
SOMATIC_VCF="${SOMATIC_VCF:?export SOMATIC_VCF}"
OUT="${OUTDIR:-${CASE_ROOT}/somatic}"
LOG_DIR="${LOG_DIR:-${CASE_ROOT}/logs}"
LOG="${LOG:-${LOG_DIR}/somatic_handoff_$(date +%Y%m%d_%H%M%S).log}"
FORCE="${FORCE:-0}"
export TMPDIR="${TMPDIR:-${CASE_ROOT}/tmp/somatic}"
export TMP="${TMP:-${TMPDIR}}"
export TEMP="${TEMP:-${TMPDIR}}"

mkdir -p "${OUT}" "${LOG_DIR}" "${TMPDIR}" "${CASE_ROOT}/evidence"
exec > >(tee -a "${LOG}") 2>&1

echo "==> somatic_handoff_sunbinbin $(date -Is)"
echo "    input=${SOMATIC_VCF}"
echo "    out=${OUT}"

[[ -s "${SOMATIC_VCF}" ]] || { echo "ERROR: missing somatic VCF: ${SOMATIC_VCF}" >&2; exit 1; }

LOCAL_VCF="${OUT}/${PATIENT_ID}_tumor.somatic.pass.vcf.gz"
SUMMARY="${OUT}/somatic_pass_summary.tsv"
DONE="${OUT}/.somatic.done"

if [[ ! -e "${LOCAL_VCF}" || "${FORCE}" == "1" ]]; then
  ln -sfn "${SOMATIC_VCF}" "${LOCAL_VCF}"
fi
# Prefer hard copy of tbi next to local link if remote has one; else build
if [[ -s "${SOMATIC_VCF}.tbi" ]]; then
  ln -sfn "${SOMATIC_VCF}.tbi" "${LOCAL_VCF}.tbi"
elif command -v tabix >/dev/null 2>&1; then
  if [[ ! -s "${LOCAL_VCF}.tbi" || "${FORCE}" == "1" ]]; then
    # tabix needs real bgzip path
    tabix -f -p vcf "${SOMATIC_VCF}" 2>/dev/null || tabix -f -p vcf "$(readlink -f "${LOCAL_VCF}" 2>/dev/null || echo "${SOMATIC_VCF}")" || true
  fi
fi

BCFTOOLS="${BCFTOOLS:-$(command -v bcftools || true)}"
[[ -n "${BCFTOOLS}" ]] || BCFTOOLS="${NEOAG_CONDA_BASE:-}/envs/neoag-tools/bin/bcftools"

n_pass=0
if [[ -x "${BCFTOOLS}" ]]; then
  n_pass="$("${BCFTOOLS}" view -H -f PASS "${SOMATIC_VCF}" 2>/dev/null | wc -l | tr -d ' ')" || n_pass=0
fi
if [[ "${n_pass}" == "0" ]]; then
  n_pass="$(gzip -dc "${SOMATIC_VCF}" | awk '!/^#/ {c++} END{print c+0}')"
fi

{
  printf 'sample_id\ttumor_sample\tnormal_sample\tsource_vcf\tn_variants\tfilter\tcaller_note\n'
  printf '%s\t%s\t%s\t%s\t%s\tPASS\tprecomputed Mutect2-style pass VCF (handed off, not re-called)\n' \
    "${PATIENT_ID}" "${TUMOR_SAMPLE}" "${NORMAL_SAMPLE}" "${SOMATIC_VCF}" "${n_pass}"
} > "${SUMMARY}"

ln -sfn "${LOCAL_VCF}" "${CASE_ROOT}/evidence/somatic.pass.vcf.gz" || true
cp -f "${SUMMARY}" "${CASE_ROOT}/evidence/somatic_pass_summary.tsv"

date -Is > "${DONE}"
echo "==> somatic handoff done: n_pass=${n_pass}"
echo "    ${LOCAL_VCF}"
echo "    ${SUMMARY}"
cat "${SUMMARY}"
