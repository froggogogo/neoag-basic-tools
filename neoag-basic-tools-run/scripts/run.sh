#!/usr/bin/env bash
# One-shot basic-tools run + production (sunbinbin DAG).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/dispatch.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run.sh --case-root DIR --sample-id ID [options]
  bash scripts/probe_host.sh [--json]

Required:
  --case-root DIR     病例工作目录（hla/ sequenza/ short-rna/ 写在这里）
  --sample-id ID      样本名

Inputs (as needed by stages):
  --tumor-bam PATH --normal-bam PATH --somatic-vcf PATH
  --rna-r1 PATH --rna-r2 PATH
  --deps-dir DIR      默认 /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps
  --neo-root DIR      完整 neo 仓库（生产接口 python -m neoag.production_runner）
  --mode serial|dual|full   默认由 probe_host 决定
  --skip-production   只跑基础工具
  --yes

Modes:
  probe  只探查核数/内存
  plan   打印调度，不跑
  run    探查 + 基础工具 + 生产（默认）
EOF
}

MODE_CMD="run"
CASE_ROOT=""
SAMPLE_ID=""
DEPS_DIR="${DEFAULT_DEPS_DIR}"
NEO_ROOT="${NEOAG_ROOT:-}"
TUMOR_BAM=""
NORMAL_BAM=""
SOMATIC_VCF=""
RNA_R1=""
RNA_R2=""
SCHED_MODE=""
SKIP_PRODUCTION=0
YES=0
FORCE="${FORCE:-0}"
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE_CMD="${2:?}"; shift 2 ;;
    --case-root) CASE_ROOT="${2:?}"; shift 2 ;;
    --sample-id) SAMPLE_ID="${2:?}"; shift 2 ;;
    --deps-dir) DEPS_DIR="${2:?}"; shift 2 ;;
    --neo-root) NEO_ROOT="${2:?}"; shift 2 ;;
    --tumor-bam) TUMOR_BAM="${2:?}"; shift 2 ;;
    --normal-bam) NORMAL_BAM="${2:?}"; shift 2 ;;
    --somatic-vcf) SOMATIC_VCF="${2:?}"; shift 2 ;;
    --rna-r1) RNA_R1="${2:?}"; shift 2 ;;
    --rna-r2) RNA_R2="${2:?}"; shift 2 ;;
    --sched) SCHED_MODE="${2:?}"; shift 2 ;;
    --skip-production) SKIP_PRODUCTION=1; shift ;;
    --force) FORCE=1; shift ;;
    --yes|-y) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "BAD_ARG" "未知参数: $1" ;;
  esac
done

export FORCE CONTINUE_ON_ERROR DEPS_DIR CASE_ROOT SAMPLE_ID NEO_ROOT
export TUMOR_BAM NORMAL_BAM SOMATIC_VCF RNA_R1 RNA_R2
export PATIENT_ID="${SAMPLE_ID}"

if [[ -f "${DEPS_DIR}/configs/bootstrap_case.sh" ]]; then
  # shellcheck disable=SC1090
  source "${DEPS_DIR}/configs/bootstrap_case.sh"
elif [[ -f "${DEPS_DIR}/configs/site.env.sh" ]]; then
  # shellcheck disable=SC1090
  source "${DEPS_DIR}/configs/site.env.sh"
fi

probe_text() { bash "${SCRIPT_DIR}/probe_host.sh"; }
probe_mode() {
  bash "${SCRIPT_DIR}/probe_host.sh" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["mode"])'
}

if [[ "$MODE_CMD" == "probe" ]]; then
  probe_text
  exit 0
fi

[[ -n "$CASE_ROOT" && -n "$SAMPLE_ID" ]] || die "NEED_CASE" "需要 --case-root 与 --sample-id"
CASE_ROOT="$(cd "$CASE_ROOT" && pwd -P)"
export CASE_ROOT
ensure_case_layout "$CASE_ROOT"
export_case_env

if [[ -z "$SCHED_MODE" ]]; then
  SCHED_MODE="$(probe_mode)"
fi
export SCHED_MODE

print_plan() {
  probe_text
  cat <<EOF
======== run plan ========
sample:     ${SAMPLE_ID}
case-root:  ${CASE_ROOT}
deps-dir:   ${DEPS_DIR}
neo-root:   ${NEO_ROOT:-"(unset — 生产接口需要)"}
sched:      ${SCHED_MODE}
tumor-bam:  ${TUMOR_BAM:-"(unset)"}
normal-bam: ${NORMAL_BAM:-"(unset)"}
somatic:    ${SOMATIC_VCF:-"(unset)"}
rna-r1:     ${RNA_R1:-"(unset)"}
skip-prod:  ${SKIP_PRODUCTION}
DAG:
  dual/full: HLA队列 ∥ CNV队列
  full:      同时开 RNA STAR 波
  then:      LOHHLA (HLA+CNV) ; SNAF→SpliceMutr (HLA+junctions)
  then:      VEP ; production
==========================
EOF
}

run_stage() {
  local name="$1"
  log "==== stage ${name} ===="
  bash "${SCRIPT_DIR}/stages/${name}.sh"
}

if [[ "$MODE_CMD" == "plan" ]]; then
  print_plan
  exit 0
fi

[[ "$MODE_CMD" == "run" ]] || die "BAD_MODE" "未知 --mode ${MODE_CMD}"

if [[ "$YES" != "1" && -t 0 ]]; then
  read -r -p "将写入 ${CASE_ROOT}（sched=${SCHED_MODE}），继续？[y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || die "ABORTED" "用户取消"
elif [[ "$YES" != "1" ]]; then
  die "NEED_YES" "非交互请加 --yes"
fi

print_plan
STAMP="$(date +%Y%m%d_%H%M%S)"
MASTER="${CASE_ROOT}/logs/run_${STAMP}.log"
log "master log: ${MASTER}"
exec > >(tee -a "$MASTER") 2>&1

HLA_PID="" CNV_PID="" RNA_PID=""

start_hla() { run_stage hla; }
start_cnv() { run_stage cnv; }
start_rna() { run_stage rna; }

case "$SCHED_MODE" in
  full)
    log "FULL: HLA ∥ CNV ∥ RNA"
    start_hla & HLA_PID=$!
    start_cnv & CNV_PID=$!
    start_rna & RNA_PID=$!
    wait_pids "$HLA_PID" "$CNV_PID" "$RNA_PID" || warn "有并行队列失败，继续 LOHHLA/SNAF（CONTINUE_ON_ERROR=${CONTINUE_ON_ERROR})"
    ;;
  dual)
    log "DUAL: HLA ∥ CNV；然后 RNA"
    start_hla & HLA_PID=$!
    start_cnv & CNV_PID=$!
    wait_pids "$HLA_PID" "$CNV_PID" || warn "HLA/CNV 有失败"
    start_rna
    ;;
  serial)
    log "SERIAL: HLA → CNV → RNA"
    start_hla
    start_cnv
    start_rna
    ;;
  *)
    die "BAD_SCHED" "未知 sched ${SCHED_MODE}"
    ;;
esac

run_stage lohhla
run_stage snaf
run_stage splicemutr
run_stage vep

if [[ "$SKIP_PRODUCTION" == "1" ]]; then
  log "跳过生产接口"
else
  run_stage production
fi

ok "run finished sample=${SAMPLE_ID} sched=${SCHED_MODE}"
echo "logs: ${MASTER}"
echo "activate: source ${DEPS_DIR}/configs/site.env.sh"
