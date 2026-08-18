#!/usr/bin/env bash
# Production interface: generate manifest from tool results, then neoag.production_runner.
# Pattern from sunbinbin production_from_results_manifest_20260814/run_production.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"

[[ -n "${NEO_ROOT:-}" && -d "${NEO_ROOT}" ]] || die "NO_NEO_ROOT" \
  "生产接口需要完整 neo 仓库（--neo-root）。安装切片 src/neo 不够。"

CASE="${CASE_ROOT}"
SAMPLE="${SAMPLE_ID}"
DEPS="${DEPS_DIR}"
OUT="${CASE}/production_from_results_manifest_$(date +%Y%m%d)"
mkdir -p "$OUT/manifest" "$OUT/logs" "$OUT/tools"

GEN="${NEO_ROOT}/scripts/generate_production_from_results_manifest.py"
[[ -f "$GEN" ]] || die "NO_PROD_GEN" "找不到 ${GEN}"

PY="${NEOAG_CONDA_BASE:-${DEPS}/software/miniforge3}/bin/python"
[[ -x "$PY" ]] || PY="$(command -v python3)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/ensure_neo_production.sh"
ensure_neo_production "$(cd "${SCRIPT_DIR}/.." && pwd)" "$PY"

optional() {
  local p="$1"
  [[ -e "$p" ]] && printf '%s' "$p" || true
}

args=(
  --project-root "$NEO_ROOT"
  --sample-id "$SAMPLE"
  --outdir "$OUT"
  --output "$OUT/manifest/production.results.toml"
)
[[ -n "${SOMATIC_VCF:-}" ]] && args+=(--somatic-vcf "$SOMATIC_VCF")

add_if() {
  local flag="$1" path="$2"
  [[ -e "$path" ]] && args+=("$flag" "$path")
}

add_if --optitype "$CASE/hla/optitype/${SAMPLE}_blood_result.tsv"
add_if --optitype "$CASE/hla/optitype/${SAMPLE}_result.tsv"
add_if --spechla-typing "$CASE/hla/spechla/typing/normal/${SAMPLE}_blood/hla.result.txt"
add_if --hla-la "$CASE/hla/hla_la/working/${SAMPLE}_blood/hla/R1_bestguess_G.txt"
add_if --facets "$CASE/facets/omni2p5_snponly_downsample"
add_if --ascat "$CASE/ascat"
add_if --purity "$CASE/evidence/purity.tsv"
add_if --cnv "$CASE/evidence/cnv_segments.tsv"
add_if --lohhla "$CASE/evidence/hla_loh.tsv"
add_if --spechla-loh "$CASE/evidence/hla_loh.spechla.tsv"
add_if --expression "$CASE/short-rna/evidence/gene_expression.tsv"
add_if --transcript-expression "$CASE/short-rna/evidence/transcript_quant.sf"
add_if --easyfuse "$CASE/short-rna/evidence/easyfuse.fusions.pass.csv"
add_if --junctions "$CASE/short-rna/evidence/regtools_junctions.tsv"
add_if --snaf "$CASE/short-rna/snaf/snaf_candidates.tsv"
add_if --splicemutr "$CASE/short-rna/splicemutr"

add_if --normal-junctions "$DEPS/refs/normal/junctions/normal_junctions.GRCh38.tsv.gz"
add_if --normal-expression "$DEPS/refs/normal/expression/normal_expression.gtex_v11_hpa_hspc.tsv"
add_if --normal-hla-ligands "$DEPS/refs/normal/ligandome/normal_ms_ligands.tsv"
add_if --reference-proteome "$DEPS/refs/normal/proteome/gencode.v49.pc_translations.clean.fa"
NETCHOP_BIN="${DEPS}/licenses/predictors/netchop/netchop-3.1/Linux_x86_64/bin/netChop"
NETCHOP_HOME_DIR="${DEPS}/licenses/predictors/netchop/netchop-3.1"
add_if --netchop-executable "$NETCHOP_BIN"
add_if --netchop-home "$NETCHOP_HOME_DIR"

PROFILE="${NEO_ROOT}/profiles/sarcoma_rna_supported_v2_provisional.toml"
[[ -f "$PROFILE" ]] && args+=(--profile "$PROFILE")

# Skill only uses neoag_100T. Do not inherit a machine-local NETMHCSTABPAN_HOME.
STABPAN_HOME="${DEPS}/licenses/predictors/netMHCstabpan"
STABPAN_BIN="${STABPAN_HOME}/Linux_x86_64/bin/netMHCstabpan"
[[ -x "$STABPAN_BIN" && -d "${STABPAN_HOME}/data" ]] || die "NO_NETMHCSTABPAN" \
  "运行 skill 必须跑 NetMHCstabpan。缺少 DTU 树: ${STABPAN_BIN}（需要 Linux_x86_64/bin + data/，在 neoag_100T licenses/predictors/netMHCstabpan）。"
export NETMHCSTABPAN_HOME="${STABPAN_HOME}"
export NETMHCSTABPAN_BIN="${STABPAN_HOME}/netMHCstabpan"

log "generate production manifest -> ${OUT}/manifest/production.results.toml"
"$PY" "$GEN" "${args[@]}"

export NEOAG_CONDA_BASE="${NEOAG_CONDA_BASE:-${DEPS}/software/miniforge3}"
export NEOAG_TOOLS_ROOT="${DEPS}"
export NEODATA_ROOT="${DEPS}"
export NEOAG_TOOL_QUARANTINE="${DEPS}/licenses/predictors"
export NEOAG_FORCE_CPU=1
export NEOAG_PRIME_JOBS="${NEOAG_PRIME_JOBS:-4}"
export NEOAG_NETMHCPAN_LOCAL_CHUNK_SIZE="${NEOAG_NETMHCPAN_LOCAL_CHUNK_SIZE:-5000}"

if [[ -f "${NEO_ROOT}/conf/tools.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${NEO_ROOT}/conf/tools.env.sh"
fi
[[ -f "${NEO_ROOT}/conf/tools.env.local.sh" ]] && source "${NEO_ROOT}/conf/tools.env.local.sh"

export NETMHCPAN_HOME="${NETMHCPAN_HOME:-${DEPS}/licenses/predictors/netMHCpan}"
export NETMHCpan="${NETMHCpan:-${NETMHCPAN_HOME}}"
export PRIME_HOME="${PRIME_HOME:-${DEPS}/licenses/predictors/prime}"
export MIXMHCPRED_HOME="${MIXMHCPRED_HOME:-${DEPS}/licenses/predictors/mixMHCpred_install}"
export BIGMHC_DIR="${BIGMHC_DIR:-${DEPS}/licenses/predictors/bigmhc}"
export DEEPIMMUNO_DIR="${DEEPIMMUNO_DIR:-${DEPS}/licenses/predictors/DeepImmuno}"
export NEOAG_PRIME_BIN="${NEOAG_PRIME_BIN:-${PRIME_HOME}/PRIME}"
export NEOAG_PRIME_PYTHON="${NEOAG_PRIME_PYTHON:-${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python}"
export MIXMHCPRED_BIN="${MIXMHCPRED_BIN:-${MIXMHCPRED_HOME}/MixMHCpred}"
export BIGMHC_PYTHON="${BIGMHC_PYTHON:-${NEOAG_CONDA_BASE}/envs/neoag-tools/bin/python}"
export NEOAG_NETCHOP_BIN="${NEOAG_NETCHOP_BIN:-${NETCHOP_BIN:-${DEPS}/licenses/predictors/netchop/netchop-3.1/Linux_x86_64/bin/netChop}}"
export NETCHOP_HOME="${NETCHOP_HOME:-${NETCHOP_HOME_DIR:-${DEPS}/licenses/predictors/netchop/netchop-3.1}}"
export NETMHCSTABPAN_HOME="${DEPS}/licenses/predictors/netMHCstabpan"
export NETMHCSTABPAN_BIN="${NETMHCSTABPAN_HOME}/netMHCstabpan"
export PATH="${NEOAG_CONDA_BASE}/bin:${NEOAG_CONDA_BASE}/envs/neoag-tools/bin:${NETMHCPAN_HOME}:${NETMHCSTABPAN_HOME}:${PRIME_HOME}:${MIXMHCPRED_HOME}:${PATH:-}"

if [[ -f "${DEPS}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${DEPS}/configs/site.env.sh"
fi
if type neoag_use_vep_perl >/dev/null 2>&1; then
  neoag_use_vep_perl
fi

# Re-pin after site.env / overlay so machine-local HOME cannot leak in.
export NETMHCSTABPAN_HOME="${DEPS}/licenses/predictors/netMHCstabpan"
export NETMHCSTABPAN_BIN="${NETMHCSTABPAN_HOME}/netMHCstabpan"
export PATH="${NETMHCSTABPAN_HOME}:${PATH:-}"

log "neoag.production_runner --execute"
PYTHONPATH="${NEO_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" "$PY" -m neoag.production_runner \
  --manifest "$OUT/manifest/production.results.toml" \
  --project-root "$NEO_ROOT" \
  --outdir "$OUT" \
  --execute

ok "production finished out=${OUT}"
echo "reports: ${OUT}/final/reports/"
