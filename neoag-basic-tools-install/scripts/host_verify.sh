#!/usr/bin/env bash
# Per-host basic-tool readiness (not just shared refs).
# Usage: source site.env.sh; bash scripts/host_verify.sh
set -euo pipefail
DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
if [[ -f "${DEPS}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  NEOAG_SITE_QUIET=1 source "${DEPS}/configs/site.env.sh"
fi

BASE="${NEOAG_CONDA_BASE:-}"
E="${BASE}/envs"
os="unknown"
ef=0
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  os="${PRETTY_NAME:-unknown}"
  [[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == "22.04" ]] && ef=1
fi

ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
miss() { printf 'MISSING\t%s\t%s\n' "$1" "$2"; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

printf 'host\t%s\n' "$(hostname)"
printf 'os\t%s\n' "$os"
printf 'conda\t%s\n' "${BASE:-MISSING}"
printf 'neo_root\t%s\n' "${NEOAG_ROOT:-}"
printf 'tools_root\t%s\n' "${NEOAG_TOOLS_ROOT:-}"
printf 'easyfuse_os\t%s\n' "$ef"
printf -- '----\n'
printf 'status\titem\tdetail\n'

has_bin() { [[ -n "${1:-}" && -x "$1" ]]; }

item() {
  local label="$1" path="$2"
  if has_bin "$path" || [[ -d "$path" && -n "$(ls -A "$path" 2>/dev/null || true)" ]]; then
    ok "$label" "$path"
  else
    miss "$label" "${path:-unset}"
  fi
}

item "env:neoag-tools" "${E}/neoag-tools"
item "env:neoag-fusion" "${E}/neoag-fusion"
item "bin:STAR" "${STAR_BIN:-${E}/neoag-fusion/bin/STAR}"
item "bin:salmon" "${SALMON_BIN:-${E}/neoag-salmon-cpp/bin/salmon}"
item "env:neoag-splice" "${E}/neoag-splice"
item "bin:regtools" "${NEOAG_REGTOOLS_BIN:-${E}/neoag-splice/bin/regtools}"
item "env:neoag-splicemutr" "${E}/neoag-splicemutr"
item "env:neoag-sequenza" "${E}/neoag-sequenza"
item "bin:sequenza-utils" "${E}/neoag-sequenza/bin/sequenza-utils"
item "env:neoag-vep" "${E}/neoag-vep"
item "bin:vep" "${VEP_BIN:-${E}/neoag-vep/bin/vep}"
item "env:neoag-gatk" "${E}/neoag-gatk"
item "env:neoag-optitype" "${E}/neoag-optitype"
item "env:neoag-snaf" "${E}/neoag-snaf"
item "pvac:711_or_tools" "${NEOAG_PVAC_ENV:-${E}/neoag-pvactools711}"
item "bin:pvacseq" "${PVACSEQ_BIN:-${E}/neoag-pvactools711/bin/pvacseq}"
item "bin:samtools19" "${SEQUENZA_SAMTOOLS:-${E}/neoag-samtools19/bin/samtools}"
item "tool:STAR-Fusion" "${NEOAG_STAR_FUSION_HOME:-}"
item "tool:HLA-LA" "${HLALA_HOME:-}"
item "tool:SpecHLA" "${SPECHLA_HOME:-}"
if [[ "$ef" -eq 1 ]]; then
  item "tool:EasyFuse" "${NEOAG_EASYFUSE_HOME:-}"
else
  skip "tool:EasyFuse" "not Ubuntu 22.04"
fi
item "ref:chr_fasta" "${REF_FASTA:-}"
item "ref:ctat" "${CTAT_GENOME_LIB:-}"
item "ref:vep_cache" "${NEOAG_VEP_CACHE:-}"

if [[ -x "${E}/neoag-splicemutr/bin/Rscript" ]]; then
  if "${E}/neoag-splicemutr/bin/Rscript" -e 'suppressPackageStartupMessages(library(BSgenome.Hsapiens.UCSC.hg38)); cat("OK\n")' >/dev/null 2>&1; then
    ok "r:BSgenome.Hsapiens.UCSC.hg38" "neoag-splicemutr"
  else
    miss "r:BSgenome.Hsapiens.UCSC.hg38" "neoag-splicemutr"
  fi
fi
if [[ -x "${E}/neoag-sequenza/bin/Rscript" ]]; then
  if "${E}/neoag-sequenza/bin/Rscript" -e 'cat(requireNamespace("data.table", quietly=TRUE), "\n")' 2>/dev/null | grep -q TRUE; then
    ok "r:data.table" "neoag-sequenza"
  else
    miss "r:data.table" "neoag-sequenza"
  fi
fi

mf="${MHCFLURRY_DATA_DIR:-${HOME}/.local/share/mhcflurry}"
if [[ -e "${mf}/2.0.0/models_class1_presentation" || -e "${mf}/4/2.0.0/models_class1_presentation" ]]; then
  ok "mhcflurry:models" "$mf"
else
  miss "mhcflurry:models" "$mf"
fi

item_file() {
  local label="$1" path="$2"
  if [[ -f "$path" || -x "$path" ]]; then
    ok "$label" "$path"
  else
    miss "$label" "${path:-unset}"
  fi
}
item_file "pred:bigmhc_predict.py" "${BIGMHC_DIR:-}/src/predict.py"
item_file "pred:deepimmuno" "${DEEPIMMUNO_DIR:-}/deepimmuno-cnn.py"
item_file "pred:mixmhcpred" "${MIXMHCPRED_BIN:-${MIXMHCPRED_HOME:-}/MixMHCpred}"
item_file "pred:prime" "${NEOAG_PRIME_BIN:-${PRIME_HOME:-}/PRIME}"
item_file "pred:netchop" "${NEOAG_NETCHOP_BIN:-}"
item_file "pred:netmhcstabpan" "${NETMHCSTABPAN_BIN:-${DEPS}/licenses/predictors/netMHCstabpan/netMHCstabpan}"
