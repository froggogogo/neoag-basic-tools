#!/usr/bin/env bash
# Verify centralized deps + basic tool readiness (existence + readability + env smoke)

declare -a VERIFY_MARKERS=(
  "refs/hg38/Homo_sapiens_assembly38.fasta|hg38 FASTA|REQUIRED|file"
  "refs/hg38/Homo_sapiens_assembly38.fasta.fai|hg38 FASTA index|REQUIRED|file"
  "refs/vep|VEP cache root|REQUIRED|dir"
  "refs/hla/PRG_MHC_GRCh38_withIMGT|HLA-LA graph|REQUIRED|dir"
  "refs/hla/spechla|SpecHLA DB|REQUIRED|dir"
  "refs/easyfuse/current|EasyFuse refs|REQUIRED_IF_UBUNTU_2204|dir"
  "refs/ctat|CTAT genome lib|REQUIRED|dir"
  "refs/rna/gencode_v49/salmon_index|Salmon index|REQUIRED|dir"
  "refs/facets/reference/common_snp.hg38.vcf.gz|FACETS SNP VCF|REQUIRED|file"
  "refs/hmf/purple_reference|PURPLE refs|REQUIRED|dir"
  "refs/sequenza/reference/GRCh38.primary_assembly.chr.fa|Sequenza FASTA|REQUIRED|file"
  "tools/sequenza/bam2seqz_nulsafe.py|Sequenza bam2seqz NUL wrapper|REQUIRED|file"
  "tools/sequenza/run_sequenza_steps.sh|Sequenza pileup+fit runner|REQUIRED|file"
  "refs/ascat/reference/WGS_hg38|ASCAT WGS refs|REQUIRED|dir"
  "refs/snaf|SNAF refs|REQUIRED|dir"
  "refs/lohhla/polysolver|Polysolver home|OPTIONAL_LICENSED|dir"
  "refs/lohhla/novoalign.lic|Novoalign license|OPTIONAL_LICENSED|file"
  "licenses/predictors/netMHCpan|NetMHCpan|OPTIONAL_LICENSED|dir"
  "licenses/predictors/netMHCstabpan/Linux_x86_64/bin/netMHCstabpan|NetMHCstabpan DTU binary|OPTIONAL_LICENSED|file"
  "licenses/predictors/bigmhc/src/predict.py|BigMHC-IM predict.py|OPTIONAL_LICENSED|file"
  "licenses/predictors/DeepImmuno/deepimmuno-cnn.py|DeepImmuno-CNN|OPTIONAL_LICENSED|file"
  "licenses/predictors/mixMHCpred_install/MixMHCpred|MixMHCpred|OPTIONAL_LICENSED|file"
  "licenses/predictors/prime/PRIME|PRIME|OPTIONAL_LICENSED|file"
  "configs/site.env.sh|site.env.sh|REQUIRED|file"
  "src/neo/conda/env.neoag-tools.yml|install-slice env yml|REQUIRED|file"
  "src/neo/scripts/install_vep.sh|install-slice tool script|REQUIRED|file"
  "src/neo/scripts/run_sequenza_fit.R|install-slice sequenza fit|REQUIRED|file"
)

# env_name|R_or_bin smoke hint
declare -a VERIFY_ENVS=(
  "neoag-tools"
  "neoag-fusion"
  "neoag-splice"
  "neoag-splicemutr"
  "neoag-sequenza"
  "neoag-vep"
  "neoag-gatk"
)

# path under DEPS_DIR that must not be an unreadable external symlink for REQUIRED items
path_probe_status() {
  local path="$1"
  local kind="${2:-any}" # file|dir|any
  local status detail="-"
  detail="-"

  if [[ -L "$path" ]]; then
    if [[ ! -e "$path" ]]; then
      echo "BROKEN_LINK|symlink target missing — 用 --sync-mode copy 或挂载 asset-source"
      return
    fi
    if ! asset_readable "$path"; then
      echo "UNREADABLE_LINK|软链目标不可读（权限/未挂载）— 改用 --mode sync --sync-mode copy"
      return
    fi
    if is_external_symlink "$path"; then
      detail="EXTERNAL_SYMLINK -> $(readlink "$path")"
      # still OK if readable, but mark for report
      echo "OK_EXTERNAL_SYMLINK|${detail}"
      return
    fi
  fi

  if [[ ! -e "$path" ]]; then
    echo "MISSING|-"
    return
  fi

  if [[ "$kind" == "file" && ! -f "$path" && ! -L "$path" ]]; then
    echo "NOT_FILE|expected file"
    return
  fi
  if [[ "$kind" == "dir" && ! -d "$path" ]]; then
    echo "NOT_DIR|expected directory"
    return
  fi

  if ! asset_readable "$path"; then
    echo "UNREADABLE|path exists but not readable by current user"
    return
  fi

  echo "OK|-"
}

verify_r_package() {
  local env="$1"
  local pkg="$2"
  local envdir="$3"
  local rscript="${envdir}/bin/Rscript"
  if [[ ! -x "$rscript" ]]; then
    echo "NO_RSCRIPT"
    return 1
  fi
  if "$rscript" -e "suppressPackageStartupMessages(library(${pkg})); cat('OK\n')" >/dev/null 2>&1; then
    echo "OK"
    return 0
  fi
  echo "MISSING_PKG"
  return 1
}

verify_installation() {
  local root="${DEPS_DIR}"
  [[ -d "$root" ]] || die "DEPS_MISSING" "依赖目录不存在: $root。请先 --mode install 初始化。"

  refresh_easyfuse_capability

  ensure_dir "${root}/manifests" 777
  local report="${root}/manifests/verify_report.tsv"
  printf 'path\tlabel\tclass\tstatus\tdetail\n' >"$report"

  local item rel label class kind path status detail effective_class probe
  local req_fail=0 opt_miss=0 ext_symlink=0

  for item in "${VERIFY_MARKERS[@]}"; do
    IFS='|' read -r rel label class kind <<<"$item"
    path="${root}/${rel}"
    detail="-"
    effective_class="$class"

    if [[ "$class" == "REQUIRED_IF_UBUNTU_2204" ]]; then
      if [[ "${NEOAG_EASYFUSE_SUPPORTED}" == "1" ]]; then
        effective_class="REQUIRED"
      else
        effective_class="OPTIONAL_OS"
        detail="${NEOAG_EASYFUSE_SKIP_REASON}"
      fi
    fi

    IFS='|' read -r status detail <<<"$(path_probe_status "$path" "$kind")"
    if [[ "$status" == "OK_EXTERNAL_SYMLINK" ]]; then
      ext_symlink=$((ext_symlink + 1))
      status="OK"
      # keep detail
    fi

    if [[ "$status" == "OK" ]]; then
      :
    else
      if [[ "$effective_class" == "OPTIONAL_OS" ]]; then
        [[ "$status" == "MISSING" ]] && status="SKIPPED_OS"
        opt_miss=$((opt_miss + 1))
      elif [[ "$effective_class" == "REQUIRED" ]]; then
        req_fail=$((req_fail + 1))
      else
        opt_miss=$((opt_miss + 1))
      fi
    fi

    echo -e "${path}\t${label}\t${effective_class}\t${status}\t${detail}" >>"$report"
    if [[ "$status" == "OK" ]]; then
      ok "VERIFY ${label}: ${path}${detail:+ (${detail})}"
    else
      warn "VERIFY ${label}: ${status} (${path}) ${detail}"
    fi
  done

  local gc_wig=""
  for gc_wig in \
    "${root}/refs/sequenza/reference/Homo_sapiens.GRCh38.dna.primary_assembly.chr.gc50.wig.gz" \
    "${root}/refs/sequenza/reference/GRCh38.gc50.wig.gz"
  do
    if [[ -s "$gc_wig" ]]; then
      ok "VERIFY Sequenza GC wiggle: ${gc_wig}"
      echo -e "${gc_wig}\tSequenza GC wiggle\tREQUIRED\tOK\t-" >>"$report"
      gc_wig="FOUND"
      break
    fi
  done
  if [[ "$gc_wig" != "FOUND" ]]; then
    warn "VERIFY Sequenza GC wiggle missing under refs/sequenza/reference/"
    echo -e "${root}/refs/sequenza/reference/*.gc50.wig.gz\tSequenza GC wiggle\tREQUIRED\tMISSING\tsync data/sequenza" >>"$report"
    req_fail=$((req_fail + 1))
  fi

  if [[ "$ext_symlink" -gt 0 ]]; then
    warn "有 ${ext_symlink} 项 refs 仍是指向 deps 外的软链。其它机器若读不到源盘会失败；建议: bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync"
  fi

  # EasyFuse capability
  if [[ "${NEOAG_EASYFUSE_SUPPORTED}" == "1" ]]; then
    echo -e "capability:easyfuse\tEasyFuse runtime\tOS\tSUPPORTED\tUbuntu 22.04" >>"$report"
    ok "VERIFY EasyFuse runtime: SUPPORTED on this host"
  else
    echo -e "capability:easyfuse\tEasyFuse runtime\tOS\tUNSUPPORTED\t${NEOAG_EASYFUSE_SKIP_REASON}" >>"$report"
    warn "VERIFY EasyFuse runtime: UNSUPPORTED on this host"
  fi

  # Conda / tools smoke
  if discover_conda 2>/dev/null; then
    ok "VERIFY conda: ${CONDA_EXE}"
    echo -e "conda\tconda\tENV\tOK\t${CONDA_EXE}" >>"$report"
    if is_network_fs "${CONDA_BASE}" 2>/dev/null; then
      warn "VERIFY conda 在网络盘上: ${CONDA_BASE}（FUSE/NFS 上的 conda 不稳定）"
      echo -e "conda_location\tconda_in_deps\tPORTABILITY\tNETWORK_FS\t${CONDA_BASE}" >>"$report"
    else
      ok "VERIFY conda on host disk: ${CONDA_BASE}"
      echo -e "conda_location\tconda_host\tPORTABILITY\tOK\t${CONDA_BASE}" >>"$report"
    fi

    local env envdir
    for env in "${VERIFY_ENVS[@]}"; do
      envdir="${CONDA_BASE}/envs/${env}"
      if [[ -d "$envdir" ]]; then
        ok "VERIFY env ${env}"
        echo -e "conda:${env}\t${env}\tENV\tOK\t${envdir}" >>"$report"
      else
        warn "VERIFY env missing: ${env}"
        echo -e "conda:${env}\t${env}\tENV\tMISSING\trun --mode envs --yes" >>"$report"
        req_fail=$((req_fail + 1))
      fi
    done

    # Critical R genome packages (SpliceMutr / Sequenza)
    local sm_dir="${CONDA_BASE}/envs/neoag-splicemutr"
    if [[ -d "$sm_dir" ]]; then
      local st
      st="$(verify_r_package neoag-splicemutr BSgenome "$sm_dir")"
      if [[ "$st" == "OK" ]]; then
        ok "VERIFY R: BSgenome in neoag-splicemutr"
        echo -e "r:BSgenome\tBSgenome\tRPKG\tOK\tneoag-splicemutr" >>"$report"
      else
        warn "VERIFY R: BSgenome ${st}"
        echo -e "r:BSgenome\tBSgenome\tRPKG\t${st}\tneoag-splicemutr" >>"$report"
        req_fail=$((req_fail + 1))
      fi
      st="$(verify_r_package neoag-splicemutr BSgenome.Hsapiens.UCSC.hg38 "$sm_dir")"
      if [[ "$st" == "OK" ]]; then
        ok "VERIFY R: BSgenome.Hsapiens.UCSC.hg38 in neoag-splicemutr"
        echo -e "r:BSgenome.Hsapiens.UCSC.hg38\tBSgenome.Hsapiens.UCSC.hg38\tRPKG\tOK\tneoag-splicemutr" >>"$report"
      else
        warn "VERIFY R: BSgenome.Hsapiens.UCSC.hg38 ${st} — SpliceMutr 会在运行期失败"
        echo -e "r:BSgenome.Hsapiens.UCSC.hg38\tBSgenome.Hsapiens.UCSC.hg38\tRPKG\t${st}\trun ensure genome pkgs / BiocManager" >>"$report"
        req_fail=$((req_fail + 1))
      fi
    fi

    local sq_dir="${CONDA_BASE}/envs/neoag-sequenza"
    if [[ -d "$sq_dir" ]]; then
      if "${sq_dir}/bin/Rscript" -e 'suppressPackageStartupMessages(library(sequenza)); cat("OK\n")' >/dev/null 2>&1; then
        ok "VERIFY R: sequenza in neoag-sequenza"
        echo -e "r:sequenza\tsequenza\tRPKG\tOK\tneoag-sequenza" >>"$report"
      else
        warn "VERIFY R: sequenza package missing/unloadable"
        echo -e "r:sequenza\tsequenza\tRPKG\tMISSING_PKG\tneoag-sequenza" >>"$report"
        req_fail=$((req_fail + 1))
      fi
      if "${sq_dir}/bin/Rscript" -e 'cat(requireNamespace("data.table", quietly=TRUE), "\n")' 2>/dev/null | grep -q TRUE; then
        ok "VERIFY R: data.table in neoag-sequenza"
        echo -e "r:data.table\tdata.table\tRPKG\tOK\tneoag-sequenza" >>"$report"
      else
        warn "VERIFY R: data.table missing — Sequenza fit fread 补丁会失败"
        echo -e "r:data.table\tdata.table\tRPKG\tMISSING_PKG\trun ensure_sequenza_datatable / conda install r-data.table" >>"$report"
        req_fail=$((req_fail + 1))
      fi
      if [[ -x "${sq_dir}/bin/sequenza-utils" ]]; then
        ok "VERIFY bin: sequenza-utils"
        echo -e "bin:sequenza-utils\tsequenza-utils\tBIN\tOK\t${sq_dir}/bin/sequenza-utils" >>"$report"
      else
        warn "VERIFY bin: sequenza-utils missing in neoag-sequenza"
        echo -e "bin:sequenza-utils\tsequenza-utils\tBIN\tMISSING\t${sq_dir}" >>"$report"
        req_fail=$((req_fail + 1))
      fi
    fi

    local st19="${CONDA_BASE}/envs/neoag-samtools19/bin/samtools"
    local st_ok=0
    if [[ -x "$st19" ]]; then
      ok "VERIFY samtools 1.9 (neoag-samtools19)"
      echo -e "bin:samtools19\tsamtools\tBIN\tOK\t${st19}" >>"$report"
      st_ok=1
    elif [[ -x "${sq_dir:-}/bin/samtools" ]]; then
      local stv
      stv="$("${sq_dir}/bin/samtools" --version 2>/dev/null | awk 'NR==1{print $2}')"
      if [[ "$stv" == 1.9* ]]; then
        ok "VERIFY samtools 1.9 (neoag-sequenza ${stv})"
        echo -e "bin:samtools19\tsamtools\tBIN\tOK\t${sq_dir}/bin/samtools ${stv}" >>"$report"
        st_ok=1
      fi
    fi
    if [[ "$st_ok" -eq 0 ]]; then
      warn "VERIFY samtools 1.9 missing — bam2seqz 可用 NUL wrapper + 较新 samtools，但 gold 路径是 1.9"
      echo -e "bin:samtools19\tsamtools\tBIN\tMISSING\tconda env neoag-samtools19 samtools=1.9" >>"$report"
      opt_miss=$((opt_miss + 1))
    fi

    # MHCflurry models layout (optional for structure, required for ranking)
    local mf_ok=0
    local mf
    for mf in \
      "${DEPS_DIR}/packages/mhcflurry_data" \
      "${HOME:-}/.local/share/mhcflurry" \
      "/home/na/.local/share/mhcflurry"
    do
      [[ -n "$mf" && -d "$mf" ]] || continue
      if [[ -e "${mf}/2.0.0/models_class1_presentation" || -e "${mf}/4/2.0.0/models_class1_presentation" ]]; then
        ok "VERIFY MHCflurry models under ${mf}"
        echo -e "mhcflurry:models\tmodels_class1_presentation\tASSET\tOK\t${mf}" >>"$report"
        mf_ok=1
        break
      fi
    done
    if [[ "$mf_ok" -eq 0 ]]; then
      warn "VERIFY MHCflurry models missing — unified_ranking/mhcflurry-predict 会失败"
      echo -e "mhcflurry:models\tmodels_class1_presentation\tASSET\tMISSING\tmhcflurry-downloads fetch models_class1_presentation" >>"$report"
      # optional: do not increment req_fail (licensed/user download); keep as soft warn
      opt_miss=$((opt_miss + 1))
    fi
  else
    warn "VERIFY conda: not found"
    echo -e "conda\tconda\tENV\tMISSING\t-" >>"$report"
    req_fail=$((req_fail + 1))
  fi

  # Sequenza chrom-split fread patch (gold: sunbinbin 2026-08-17)
  local fit_r="${DEPS_DIR}/src/neo/scripts/run_sequenza_fit.R"
  [[ -f "$fit_r" ]] || fit_r="${DEPS_DIR}/tools/sequenza/run_sequenza_fit.R"
  if [[ -f "$fit_r" ]]; then
    if grep -q 'split_seqz_by_chrom' "$fit_r" && grep -q 'assignInNamespace' "$fit_r"; then
      ok "VERIFY sequenza chrom-split fread patch present"
      echo -e "patch:sequenza_fit_chromsplit\trun_sequenza_fit.R\tPATCH\tOK\t${fit_r}" >>"$report"
    else
      warn "VERIFY sequenza fit 尚未含 chrom-split fread — 见 apply_sequenza_fit_fread_patch.sh"
      echo -e "patch:sequenza_fit_chromsplit\trun_sequenza_fit.R\tPATCH\tMISSING\tbash scripts/apply_sequenza_fit_fread_patch.sh --fit-r ${fit_r}" >>"$report"
      opt_miss=$((opt_miss + 1))
    fi
  fi

  chmod a+rw "$report" 2>/dev/null || true
  log "验收报告: $report"
  log "required_failures=${req_fail} optional_missing=${opt_miss} external_symlinks=${ext_symlink} easyfuse_supported=${NEOAG_EASYFUSE_SUPPORTED}"

  if [[ "$req_fail" -gt 0 ]]; then
    die "VERIFY_FAILED" \
      "有 ${req_fail} 项必需依赖未就绪。请检查 sync/copy/envs，或查看 ${report}。"
  fi
  ok "验收通过（必需项齐全）。可选/系统跳过项 ${opt_miss} 不影响结构验收。"
}
