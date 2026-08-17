#!/usr/bin/env bash
# Create basic conda environments (A1 profile) + critical genome R packages

# name|yml_relpath_under_neo
BASIC_ENV_SPECS=(
  "neoag-tools|conda/env.neoag-tools.yml"
  "neoag-fusion|conda/env.neoag-fusion.yml"
  "neoag-splice|conda/env.neoag-splice.yml"
  "neoag-splicemutr|conda/env.neoag-splicemutr.yml"
  "neoag-sequenza|conda/env.neoag-sequenza.yml"
  "neoag-vep|conda/env.neoag-vep.yml"
  "neoag-gatk|conda/env.neoag-gatk.yml"
)

# Ensure genome-specific BSgenome in splicemutr env (yml often only has core BSgenome).
ensure_splicemutr_genome_pkgs() {
  local env_prefix="${CONDA_BASE}/envs/neoag-splicemutr"
  local rscript="${env_prefix}/bin/Rscript"
  [[ -d "$env_prefix" ]] || return 0
  [[ -x "$rscript" ]] || {
    warn "neoag-splicemutr 无 Rscript，跳过基因组包检查"
    return 0
  }

  if "$rscript" -e 'suppressPackageStartupMessages(library(BSgenome.Hsapiens.UCSC.hg38)); cat("OK\n")' >/dev/null 2>&1; then
    ok "已具备 BSgenome.Hsapiens.UCSC.hg38"
    return 0
  fi

  log "安装 BSgenome.Hsapiens.UCSC.hg38 到 neoag-splicemutr（SpliceMutr 运行必需）"
  # Prefer mamba/conda bioconda; fall back to BiocManager
  if conda_frontend install -y -n neoag-splicemutr -c bioconda -c conda-forge \
      bioconductor-bsgenome.hsapiens.ucsc.hg38 2>"${DEPS_DIR}/logs/bsgenome_conda.err"; then
    ok "mamba/conda 安装 BSgenome.Hsapiens.UCSC.hg38 成功"
  else
    warn "mamba/conda 安装失败，尝试 BiocManager（见 logs/bsgenome_conda.err）"
    if ! "$rscript" -e 'if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org"); BiocManager::install("BSgenome.Hsapiens.UCSC.hg38", ask=FALSE, update=FALSE)' \
      >"${DEPS_DIR}/logs/bsgenome_bioc.out" 2>"${DEPS_DIR}/logs/bsgenome_bioc.err"; then
      warn "BiocManager 安装 BSgenome.Hsapiens.UCSC.hg38 失败；verify 将标红。日志: ${DEPS_DIR}/logs/bsgenome_bioc.err"
      return 1
    fi
  fi

  if "$rscript" -e 'suppressPackageStartupMessages(library(BSgenome.Hsapiens.UCSC.hg38)); cat("OK\n")' >/dev/null 2>&1; then
    ok "BSgenome.Hsapiens.UCSC.hg38 冒烟通过"
    return 0
  fi
  warn "安装后仍无法 library(BSgenome.Hsapiens.UCSC.hg38)"
  return 1
}

install_basic_envs() {
  [[ -n "${CONDA_EXE:-}" && -x "${CONDA_EXE}" ]] || die "NO_CONDA" "未解析到 conda，无法创建环境"
  resolve_mamba_exe
  local neo="${DEPS_DIR}/src/neo"
  if [[ ! -d "$neo" ]]; then
    die "NO_NEO_SRC" "缺少 ${neo}。请确认共享 deps 已含 src/neo 安装切片，或用 --neo-src 灌入一次（不必 clone neo 仓库）。"
  fi

  ensure_dir "${DEPS_DIR}/packages/conda_pkgs" 1777
  ensure_dir "${DEPS_DIR}/logs" 777
  export CONDA_PKGS_DIRS="${DEPS_DIR}/packages/conda_pkgs"

  local spec name yml_rel yml env_prefix
  local pass=0 fail=0
  printf 'env\tyaml\tstatus\tdetail\tfrontend\n' >"${DEPS_DIR}/manifests/conda_envs.tsv"

  for spec in "${BASIC_ENV_SPECS[@]}"; do
    name="${spec%%|*}"
    yml_rel="${spec##*|}"
    yml="${neo}/${yml_rel}"
    if [[ ! -f "$yml" ]]; then
      warn "缺少 env 文件: $yml"
      echo -e "${name}\t${yml}\tMISSING_YAML\t-\t-" >>"${DEPS_DIR}/manifests/conda_envs.tsv"
      fail=$((fail + 1))
      continue
    fi
    env_prefix="$(cd "$(dirname "${CONDA_EXE}")/.." && pwd -P)/envs/${name}"
    if [[ -d "${env_prefix}" ]]; then
      ok "conda env 已存在: $name (${env_prefix})"
      echo -e "${name}\t${yml}\tEXISTS\t${env_prefix}\t-" >>"${DEPS_DIR}/manifests/conda_envs.tsv"
      pass=$((pass + 1))
      continue
    fi
    log "创建 env (via ${CONDA_FRONTEND##*/}): $name <- $yml"
    if conda_frontend env create -n "$name" -f "$yml"; then
      ok "创建成功: $name"
      echo -e "${name}\t${yml}\tCREATED\t-\t${CONDA_FRONTEND}" >>"${DEPS_DIR}/manifests/conda_envs.tsv"
      pass=$((pass + 1))
    else
      err "创建失败: $name"
      echo -e "${name}\t${yml}\tFAIL\tsee logs\t${CONDA_FRONTEND}" >>"${DEPS_DIR}/manifests/conda_envs.tsv"
      fail=$((fail + 1))
      if [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
        die "ENV_CREATE_FAILED" "env create 失败: $name（frontend=${CONDA_FRONTEND}）。可加 --continue-on-error 跳过并继续。"
      fi
    fi
  done

  # Critical post-step for SpliceMutr
  if ! ensure_splicemutr_genome_pkgs; then
    fail=$((fail + 1))
    if [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
      die "BSGENOME_HG38_MISSING" \
        "neoag-splicemutr 缺少 BSgenome.Hsapiens.UCSC.hg38。见 ${DEPS_DIR}/logs/bsgenome_*.err；或加 --continue-on-error。"
    fi
  fi

  # Sequenza fit fread path needs data.table (see references/runtime-hardening.md)
  if declare -F ensure_sequenza_datatable >/dev/null 2>&1; then
    if ! ensure_sequenza_datatable; then
      fail=$((fail + 1))
      if [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
        die "DATATABLE_MISSING" \
          "neoag-sequenza 缺少 r-data.table。见 ${DEPS_DIR}/logs/r_datatable_conda.err；或加 --continue-on-error。"
      fi
    fi
  fi

  # OptiType via neo script when available
  if [[ -x "${neo}/scripts/install_optitype.sh" ]]; then
    log "运行 install_optitype.sh"
    if NEOAG_CONDA_BASE="$(cd "$(dirname "${CONDA_EXE}")/.." && pwd)" \
      bash "${neo}/scripts/install_optitype.sh"; then
      ok "OptiType 安装脚本完成"
    else
      warn "OptiType 安装脚本失败（可稍后重试）"
      fail=$((fail + 1))
    fi
  fi

  chmod a+rw "${DEPS_DIR}/manifests/conda_envs.tsv" 2>/dev/null || true
  log "conda envs 汇总: pass=${pass} fail=${fail}"
  [[ "$fail" -eq 0 ]] || warn "部分环境未就绪，见 manifests/conda_envs.tsv"
}

run_tool_installers() {
  local neo="${DEPS_DIR}/src/neo"
  [[ -d "$neo" ]] || die "NO_NEO_SRC" "缺少 neo 源码树"
  [[ -n "${CONDA_EXE:-}" ]] || die "NO_CONDA" "需要 conda"

  refresh_easyfuse_capability

  # Export portable env for child scripts
  # shellcheck disable=SC1090
  source "${DEPS_DIR}/configs/site.env.sh"

  local -a scripts=(
    install_facets.sh
    install_fusion_tools.sh
    install_lohhla.sh
    install_splice_tools.sh
    install_splicemutr.sh
    install_vep.sh
    install_gatk.sh
  )
  local s
  ensure_dir "${DEPS_DIR}/logs" 777
  for s in "${scripts[@]}"; do
    if [[ ! -x "${neo}/scripts/${s}" && ! -f "${neo}/scripts/${s}" ]]; then
      warn "安装脚本不存在: ${s}"
      continue
    fi
    if [[ "$s" == "install_fusion_tools.sh" && "${NEOAG_EASYFUSE_SUPPORTED}" != "1" ]]; then
      warn "跳过 ${s} 中的 EasyFuse 运行态（非 Ubuntu 22.04）。仍将尝试安装 STAR-Fusion 等其它 fusion 组件。"
      warn "详情: ${NEOAG_EASYFUSE_SKIP_REASON}"
      export NEOAG_SKIP_EASYFUSE=1
    else
      export NEOAG_SKIP_EASYFUSE=0
    fi
    log "执行 ${s}"
    if bash "${neo}/scripts/${s}" >"${DEPS_DIR}/logs/${s}.out" 2>"${DEPS_DIR}/logs/${s}.err"; then
      ok "${s} 成功"
    else
      warn "${s} 失败，详见 ${DEPS_DIR}/logs/${s}.err"
      if [[ "${CONTINUE_ON_ERROR}" != "1" ]]; then
        die "TOOL_INSTALL_FAILED" "${s} 失败。日志: ${DEPS_DIR}/logs/${s}.err"
      fi
    fi
  done

  # Re-ensure genome pkg after install_splicemutr (script may recreate env)
  ensure_splicemutr_genome_pkgs || true
}
