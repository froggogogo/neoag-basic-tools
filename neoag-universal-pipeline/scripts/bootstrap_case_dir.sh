#!/usr/bin/env bash
# =============================================================================
# bootstrap_case_dir.sh — 从 shared_scripts 初始化新病例目录
#
# 用法:
#   bash bootstrap_case_dir.sh /path/to/case.config.sh
#   bash bootstrap_case_dir.sh --config /path/to/case.config.sh
#
# 创建:
#   $CASE_ROOT/scripts/          ← rsync from shared_scripts/case_templates
#   $CASE_ROOT/short-rna/scripts/ ← rsync from short_rna_templates
#   $CASE_ROOT/sequenza runner   ← link/copy shared_scripts/sequenza
#   $CASE_ROOT/case.config.sh    ← 若不存在则从模板复制
#   $CASE_ROOT/tmp logs evidence ...
#
# 依赖: SHARED_SCRIPTS, NEOAG_BASIC_DEPS_DIR (via load_config)
# =============================================================================
set -euo pipefail

UP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${UP}/scripts/lib/load_config.sh" "${1:-${CASE_CONFIG:-}}"

SHARED="${SHARED_SCRIPTS:-/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts}"
[[ -d "${SHARED}/case_templates" ]] || { echo "ERROR: missing ${SHARED}/case_templates" >&2; exit 1; }

echo "==> bootstrap_case_dir $(date -Is)"
echo "    CASE_ROOT=${CASE_ROOT}"
echo "    SHARED=${SHARED}"

mkdir -p "${CASE_ROOT}"/{scripts,short-rna/scripts,logs,tmp,evidence,hla,facets,sequenza,purple,ascat,lohhla,vep,pvacseq,sliding,somatic}

# DNA orchestrators + libs
rsync -a --delete \
  --exclude='*_sunbinbin.sh' \
  "${SHARED}/case_templates/" "${CASE_ROOT}/scripts/"

# Sequenza gold path (override case_templates stale copy)
rsync -a "${SHARED}/sequenza/run_sequenza_steps.sh" \
         "${SHARED}/sequenza/run_sequenza_fit.R" \
         "${SHARED}/sequenza/bam2seqz_nulsafe.py" \
         "${CASE_ROOT}/scripts/" 2>/dev/null || \
  rsync -a "${NEOAG_BASIC_DEPS_DIR}/tools/sequenza/" "${CASE_ROOT}/scripts/" 2>/dev/null || true

# RNA templates
rsync -a "${SHARED}/short_rna_templates/" "${CASE_ROOT}/short-rna/scripts/"

# portable env from deps if newer
if [[ -f "${NEOAG_BASIC_DEPS_DIR}/tools/run/lib/portable_env.sh" ]]; then
  cp -f "${NEOAG_BASIC_DEPS_DIR}/tools/run/lib/portable_env.sh" "${CASE_ROOT}/scripts/lib_portable_env.sh"
fi

# case config
if [[ ! -f "${CASE_ROOT}/case.config.sh" ]]; then
  cp -f "${UP}/config/case.config.sh.template" "${CASE_ROOT}/case.config.sh"
  echo "==> wrote ${CASE_ROOT}/case.config.sh — EDIT sample paths before running"
fi

# RNA inputs.env.sh
if [[ ! -f "${CASE_ROOT}/short-rna/inputs.env.sh" ]]; then
  if [[ -f "${CASE_ROOT}/short-rna/scripts/inputs.env.sh.template" ]]; then
    cp -f "${CASE_ROOT}/short-rna/scripts/inputs.env.sh.template" \
          "${CASE_ROOT}/short-rna/inputs.env.sh"
  fi
fi

# Symlink universal runner
ln -sfn "${UP}/scripts/run_case_all.sh" "${CASE_ROOT}/run_case_all.sh" 2>/dev/null || \
  cp -f "${UP}/scripts/run_case_all.sh" "${CASE_ROOT}/run_case_all.sh"

echo "==> bootstrap done. Next:"
echo "    1. Edit ${CASE_ROOT}/case.config.sh"
echo "    2. Edit ${CASE_ROOT}/short-rna/inputs.env.sh (if RNA)"
echo "    3. bash ${CASE_ROOT}/run_case_all.sh"
