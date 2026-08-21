#!/usr/bin/env bash
# =============================================================================
# VEP annotate sunbinbin somatic PASS VCF (Wildtype + Frameshift for pVACseq/sliding)
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
SOMATIC_VCF="${SOMATIC_VCF:-${CASE_ROOT}/somatic/${PATIENT_ID}_tumor.somatic.pass.vcf.gz}"
[[ -s "${SOMATIC_VCF}" ]] || { echo "ERROR: export SOMATIC_VCF (missing ${SOMATIC_VCF})" >&2; exit 1; }
OUT="${OUTDIR:-${CASE_ROOT}/vep}"
OUT_VCF="${OUT_VCF:-${OUT}/${PATIENT_ID}_tumor.somatic.vep.vcf}"
LOG="${LOG:-${OUT}/run.vep.log}"
THREADS="${VEP_THREADS:-4}"
FORCE="${FORCE:-0}"
export TMPDIR="${TMPDIR:-${CASE_ROOT}/tmp/vep}"
export TMP="${TMP:-${TMPDIR}}"
export TEMP="${TEMP:-${TMPDIR}}"

VEP_BIN="${VEP_BIN:-${NEOAG_VEP_BIN:-}}"
if [[ -z "${VEP_BIN}" || ! -x "${VEP_BIN}" ]]; then
  for c in \
    "${NEOAG_CONDA_BASE:-}/envs/neoag-vep105/bin/vep" \
    "${NEOAG_CONDA_BASE:-}/envs/neoag-vep/bin/vep" \
    "${NEOAG_ROOT:-}/bin/vep-neoag"; do
    [[ -n "${c}" && -x "${c}" ]] && VEP_BIN="${c}" && break
  done
fi
# Isolate conda env bin so system/neoag-gatk perl5 does not shadow Ensembl modules
VEP_ENV_BIN="$(dirname "${VEP_BIN}")"
case "${VEP_BIN}" in
  */bin/vep) ;;
  *) VEP_ENV_BIN="" ;;
esac
VEP_CACHE="${VEP_CACHE:-${NEOAG_VEP_CACHE:-}}"
if [[ -z "${VEP_CACHE}" || ! -d "${VEP_CACHE}/homo_sapiens" ]]; then
  for c in \
    "${NEOAG_BASIC_DEPS_DIR:-}/refs/vep" \
    "${NEOAG_VEP_CACHE:-}" \
    "/mnt/zjl-bgi-zzb/peixunban/gl/liup/neodata4git/data/vep"; do
    [[ -n "${c}" && -d "${c}/homo_sapiens" ]] && VEP_CACHE="${c}" && break
  done
fi
[[ -n "${VEP_CACHE}" && -d "${VEP_CACHE}/homo_sapiens" ]] || {
  echo "ERROR: VEP cache missing (set VEP_CACHE / NEOAG_VEP_CACHE)" >&2
  exit 1
}
PLUGIN_DIR="${VEP_PLUGIN_DIR:-${NEOAG_VEP_PLUGINS:-}}"
if [[ -z "${PLUGIN_DIR}" || ! -f "${PLUGIN_DIR}/Wildtype.pm" ]]; then
  for c in \
    "${NEOAG_BASIC_DEPS_DIR:-}/work/vep_plugins" \
    "${NEOAG_PVAC_ENV:-}/lib/python3.11/site-packages/pvactools/tools/pvacseq/VEP_plugins" \
    "${NEOAG_CONDA_BASE:-}/envs/neoag-pvactools711/lib/python3.11/site-packages/pvactools/tools/pvacseq/VEP_plugins" \
    "${NEOAG_CONDA_BASE:-}/envs/neoag-tools/lib/python3.11/site-packages/pvactools/tools/pvacseq/VEP_plugins"; do
    [[ -n "${c}" && -f "${c}/Wildtype.pm" && -f "${c}/Frameshift.pm" ]] && PLUGIN_DIR="${c}" && break
  done
fi
REF_FASTA="${VEP_FASTA:-${REF_FASTA:-${NEOAG_REFERENCE_FASTA}}}"

mkdir -p "${OUT}" "${TMPDIR}"
exec > >(tee -a "${LOG}") 2>&1

echo "==> vep_somatic_sunbinbin $(date -Is)"
echo "    in=${SOMATIC_VCF}"
echo "    out=${OUT_VCF}"
echo "    vep=${VEP_BIN}"
echo "    cache=${VEP_CACHE}"
echo "    plugins=${PLUGIN_DIR}"
echo "    fasta=${REF_FASTA}"

if [[ -s "${OUT_VCF}" && "${FORCE}" != "1" ]] && grep -q '##INFO=<ID=CSQ' "${OUT_VCF}" 2>/dev/null; then
  echo "==> VEP VCF already present; skip"
  date -Is > "${OUT}/.vep.done"
  exit 0
fi
[[ -s "${SOMATIC_VCF}" ]] || { echo "ERROR: somatic VCF missing" >&2; exit 1; }
[[ -x "${VEP_BIN}" ]] || { echo "ERROR: VEP binary missing: ${VEP_BIN}" >&2; exit 1; }
[[ -s "${REF_FASTA}" ]] || { echo "ERROR: REF_FASTA missing: ${REF_FASTA}" >&2; exit 1; }
[[ -d "${VEP_CACHE}/homo_sapiens" ]] || { echo "ERROR: VEP cache missing under ${VEP_CACHE}" >&2; exit 1; }
[[ -f "${PLUGIN_DIR}/Wildtype.pm" && -f "${PLUGIN_DIR}/Frameshift.pm" ]] || {
  echo "ERROR: Wildtype/Frameshift plugins missing in ${PLUGIN_DIR}" >&2
  exit 1
}

rm -f "${OUT_VCF}" "${OUT_VCF}_summary.html" "${OUT_VCF}_warnings.txt"
# Clean PERL5LIB + prefer VEP env first on PATH
VEP_PATH_PREFIX="${VEP_ENV_BIN:-$(dirname "${VEP_BIN}")}"
env -u PERL5LIB -u PERL_LOCAL_LIB_ROOT -u PERL_MM_OPT -u PERL_MB_OPT \
  PATH="${VEP_PATH_PREFIX}:/usr/bin:/bin" \
  "${VEP_BIN}" \
  --input_file "${SOMATIC_VCF}" \
  --output_file "${OUT_VCF}" \
  --format vcf \
  --vcf \
  --symbol \
  --terms SO \
  --tsl \
  --hgvs \
  --canonical \
  --biotype \
  --protein \
  --fasta "${REF_FASTA}" \
  --offline \
  --cache \
  --dir_cache "${VEP_CACHE}" \
  --cache_version "${NEOAG_VEP_CACHE_VERSION:-105}" \
  --assembly GRCh38 \
  --dir_plugins "${PLUGIN_DIR}" \
  --plugin Frameshift \
  --plugin Wildtype \
  --transcript_version \
  --fork "${THREADS}" \
  --force_overwrite \
  --no_stats

grep -q '##INFO=<ID=CSQ' "${OUT_VCF}" || { echo "ERROR: CSQ missing in ${OUT_VCF}" >&2; exit 1; }
if command -v bgzip >/dev/null 2>&1 && command -v tabix >/dev/null 2>&1; then
  bgzip -f -c "${OUT_VCF}" > "${OUT_VCF}.gz"
  tabix -f -p vcf "${OUT_VCF}.gz" || true
fi
date -Is > "${OUT}/.vep.done"
echo "==> VEP done $(date -Is): ${OUT_VCF}"
