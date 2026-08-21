#!/usr/bin/env bash
# =============================================================================
# sunbinbin pVACseq (MHC-I, MHCflurry + MHCflurryEL) on VEP-annotated somatic VCF
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_ROOT="${CASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_portable_env.sh"

PATIENT_ID="${PATIENT_ID:?export PATIENT_ID}"
TUMOR_SAMPLE="${TUMOR_SAMPLE_ID:-${PATIENT_ID}_tumor}"
NORMAL_SAMPLE="${NORMAL_SAMPLE_ID:-${PATIENT_ID}_blood}"
HLA_FILE="${HLA_FILE:-${CASE_ROOT}/hla/hla_consensus.txt}"
VEP_VCF="${VEP_VCF:-${CASE_ROOT}/vep/${PATIENT_ID}_tumor.somatic.vep.vcf}"
OUT="${OUTDIR:-${CASE_ROOT}/pvacseq}"
LOG="${LOG:-${OUT}/run.pvacseq.log}"
THREADS="${PVACSEQ_THREADS:-8}"
FORCE="${FORCE:-0}"
# FACETS primary purity
TUMOR_PURITY="${TUMOR_PURITY:-}"
if [[ -z "${TUMOR_PURITY}" && -s "${CASE_ROOT}/evidence/purity.tsv" ]]; then
  TUMOR_PURITY="$(awk -F'\t' 'NR==2{print $2}' "${CASE_ROOT}/evidence/purity.tsv")"
fi
TUMOR_PURITY="${TUMOR_PURITY:-0.808}"

PVAC_ENV="${PVAC_ENV:-${NEOAG_PVAC_ENV:-${NEOAG_CONDA_BASE:-}/envs/neoag-pvactools711}}"
PVACSEQ_BIN="${PVACSEQ_BIN:-${PVAC_ENV}/bin/pvacseq}"
# Prefer case-root tmp (NAS large); isolate from other envs' TMP pollution
export TMPDIR="${TMPDIR:-${CASE_ROOT}/tmp/pvacseq}"
export TMP="${TMP:-${TMPDIR}}"
export TEMP="${TEMP:-${TMPDIR}}"
mkdir -p "${OUT}" "${TMPDIR}"
exec > >(tee -a "${LOG}") 2>&1

echo "==> pvacseq_sunbinbin $(date -Is)"
echo "    vcf=${VEP_VCF}"
echo "    tumor=${TUMOR_SAMPLE} normal=${NORMAL_SAMPLE}"
echo "    purity=${TUMOR_PURITY}"
echo "    hla=${HLA_FILE}"
echo "    out=${OUT}"
echo "    pvac_env=${PVAC_ENV}"
echo "    TMPDIR=${TMPDIR}"

[[ -s "${VEP_VCF}" ]] || { echo "ERROR: VEP VCF missing: ${VEP_VCF} (run run_vep_somatic first)" >&2; exit 1; }
[[ -s "${HLA_FILE}" ]] || { echo "ERROR: HLA file missing: ${HLA_FILE}" >&2; exit 1; }
[[ -x "${PVACSEQ_BIN}" ]] || { echo "ERROR: pvacseq missing: ${PVACSEQ_BIN}" >&2; exit 1; }

# Build comma allele list for pVACseq (use clean pvac python)
ALLELES="$(env -u PYTHONPATH -u PYTHONHOME -u TF_USE_LEGACY_KERAS \
  PATH="${PVAC_ENV}/bin:/usr/bin:/bin" \
  "${PVAC_ENV}/bin/python" - "${HLA_FILE}" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
alleles = []
for tok in re.split(r"[\s,;]+", text):
    tok = tok.strip().strip('"').strip("'")
    if not tok or tok.startswith("#"):
        continue
    if tok.upper().startswith("HLA-") and "*" in tok:
        alleles.append(tok)
    elif re.match(r"^[ABC]\*", tok):
        alleles.append("HLA-" + tok)
    elif re.match(r"^HLA-[ABC]\*", tok, re.I):
        alleles.append(tok)
seen=set(); out=[]
for a in alleles:
    if a not in seen:
        seen.add(a); out.append(a)
if not out:
    raise SystemExit("no HLA alleles parsed")
print(",".join(out))
PY
)"
echo "    alleles=${ALLELES}"

AGG="${OUT}/MHC_Class_I/${TUMOR_SAMPLE}.MHC_I.all_epitopes.aggregated.tsv"
if [[ -s "${AGG}" && "${FORCE}" != "1" ]]; then
  echo "==> pVACseq already complete: ${AGG}"
  date -Is > "${OUT}/.pvacseq.done"
  exit 0
fi

# Clean incomplete previous run always when force OR missing agg
if [[ "${FORCE}" == "1" || ! -s "${AGG}" ]]; then
  # Keep OUT but drop partial MHC dir that blocks resume sometimes
  rm -rf "${OUT}/MHC_Class_I" "${OUT}/combined" 2>/dev/null || true
fi

# Critical: strip neoag-tools/tensorflow 2.21 + TF_USE_LEGACY_KERAS pollution that
# breaks mhcflurry (keras import) inside neoag-pvactools711 (tf 2.15 + keras 2.15).
echo "==> pvacseq run (isolated env)"
env -u PYTHONPATH -u PYTHONHOME \
  -u TF_USE_LEGACY_KERAS -u KERAS_BACKEND \
  -u CONDA_PREFIX -u CONDA_DEFAULT_ENV -u CONDA_PROMPT_MODIFIER \
  PATH="${PVAC_ENV}/bin:/usr/bin:/bin" \
  TMPDIR="${TMPDIR}" TMP="${TMPDIR}" TEMP="${TMPDIR}" \
  HOME="${HOME}" \
  "${PVACSEQ_BIN}" run \
  "${VEP_VCF}" \
  "${TUMOR_SAMPLE}" \
  "${ALLELES}" \
  MHCflurry MHCflurryEL \
  "${OUT}" \
  -e1 8,9,10,11 \
  -t "${THREADS}" \
  --normal-sample-name "${NORMAL_SAMPLE}" \
  --tumor-purity "${TUMOR_PURITY}" \
  --pass-only \
  --keep-tmp-files

[[ -s "${OUT}/MHC_Class_I/${TUMOR_SAMPLE}.MHC_I.all_epitopes.tsv" ]] || {
  echo "ERROR: missing all_epitopes.tsv" >&2
  exit 1
}
[[ -s "${AGG}" ]] || { echo "ERROR: missing aggregated.tsv" >&2; exit 1; }

# handoff
mkdir -p "${CASE_ROOT}/evidence"
cp -f "${AGG}" "${CASE_ROOT}/evidence/pvacseq_aggregated.tsv"
ln -sfn "${OUT}" "${CASE_ROOT}/evidence/pvacseq" || true
date -Is > "${OUT}/.pvacseq.done"
echo "==> pVACseq done $(date -Is)"
wc -l "${OUT}/MHC_Class_I/${TUMOR_SAMPLE}.MHC_I.all_epitopes.tsv" "${AGG}" || true
