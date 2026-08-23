# 134 金标准清单（NeoAg 基础工具链）

> 审计日期：2026-08-23  
> 金标准病例：`/mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin/`  
> 说明：134 上 **无 Linux 用户 sunbinbin**；sunbinbin 为 NAS 参考病例 ID。

---

## 1. 架构（两层）

| 层 | 职责 | 金标准位置 |
|---|---|---|
| **Shell 上游** | HLA / CNV / LOHHLA / RNA / SNAF / SpliceMutr / VEP / pVAC | `shared_scripts/` → `$CASE/scripts/` |
| **Python 下游** | production_runner 证据整合（可选） | `/home/na/project/neoantigen/neoag_event_pipeline_na0707_sync_20260811` |

**运行顺序（gold path）**

1. `export PATIENT_ID TUMOR_BAM NORMAL_BAM SOMATIC_VCF`（或 `case.config.sh`）
2. `bash scripts/run_cnv_hla_parallel.sh`
3. `bash scripts/run_lohhla.sh`
4. `bash scripts/run_dna_all.sh`（或 `STAGE=downstream`）
5. `bash short-rna/scripts/run_short_rna_all.sh`（先配置 `inputs.env.sh`）
6. SNAF / SpliceMutr（`shared_scripts/snaf/`, `splicemutr/`）
7. （可选）`production_from_results_manifest_*/run_production.sh`

---

## 2. 脚本清单（canonical：`shared_scripts/`）

### 2.1 DNA 编排（`case_templates/`）

| 脚本 | 用途 |
|---|---|
| `run_cnv_hla_parallel.sh` | CNV 串行队列 ∥ HLA 串行队列 |
| `run_cnv_all.sh` | FACETS / Sequenza / PURPLE / ASCAT |
| `run_hla_all.sh` | OptiType / SpecHLA / HLA-LA / consensus |
| `run_lohhla.sh` | LOHHLA（HLA-LOH） |
| `run_dna_all.sh` | DNA 总控（prereq + downstream） |
| `run_dna_downstream_parallel.sh` | VEP / pVACseq / sliding / evidence |
| `run_dna_evidence_summary.sh` | DNA 证据汇总 |
| `run_optitype.sh` / `run_spechla.sh` / `run_hla_la.sh` / `run_polysolver.sh` | HLA 子工具 |
| `build_hla_consensus.sh` | 三工具 consensus |
| `run_purple_steps.sh` / `run_ascat_from_facets.sh` | CNV 子工具 |
| `run_somatic_handoff.sh` / `run_vep_somatic.sh` / `run_pvacseq.sh` / `run_sliding.sh` | DNA 下游 |
| `lib_portable_env.sh` / `lib_site_defaults.sh` / `lib_tool_timing.sh` | 环境库 |
| `watch_tool_runtime.sh` | 运行计时 |

### 2.2 Sequenza（`sequenza/`）

| 脚本 | 用途 |
|---|---|
| `run_sequenza_steps.sh` | **金路径**：bam2seqz → merge → bin → fit |
| `run_sequenza_fit.R` | R fit（fread 分 chrom） |
| `bam2seqz_nulsafe.py` | NUL-safe bam2seqz 包装 |

### 2.3 RNA（`short_rna_templates/`）

| 脚本 | 用途 |
|---|---|
| `run_short_rna_all.sh` | RNA 总控（Wave1–5 + evidence） |
| `run_salmon.sh` / `run_rsem.sh` / `run_star.sh` | 表达 / 比对 |
| `run_arriba.sh` / `run_star_fusion.sh` / `run_fusioncatcher.sh` / `run_easyfuse.sh` | 融合 |
| `run_regtools.sh` / `run_cis_splice.sh` | 剪接 junction |
| `run_pvacfuse.sh` / `run_pvacsplice.sh` / `run_vep_somatic_for_pvacsplice.sh` | RNA 新抗原肽 |
| `run_evidence_summary.sh` / `hla_alleles_csv.sh` | 证据汇总 |
| `inputs.env.sh.template` | RNA 配置模板 |

### 2.4 SNAF / SpliceMutr

| 路径 | 脚本 |
|---|---|
| `snaf/` | `run_snaf_pipeline.sh`, `snaf_sample_workflow.py` |
| `splicemutr/` | `run_splicemutr_patient.sh`, `prepare_splicemutr_candidates.py` |

### 2.5 na0707 Python（production，可选）

| 路径 | 用途 |
|---|---|
| `.../na0707_sync_20260811/scripts/generate_production_from_results_manifest.py` | manifest 生成 |
| `.../na0707_sync_20260811/src/neoag/production_runner.py` | 证据链 + 报告 |
| `.../profiles/sarcoma_rna_supported_v2_provisional.toml` | production profile |

---

## 3. 配置文件

| 文件 | 路径 | 说明 |
|---|---|---|
| `site.env.sh` | `neoag_100T/.../configs/site.env.sh` | 跨主机 deps + conda 解析 |
| `bootstrap_case.sh` | `neoag_100T/.../configs/bootstrap_case.sh` | 病例 env 引导 |
| `lib_site_runtime.sh` | `neoag_100T/.../configs/lib_site_runtime.sh` | 运行时解析逻辑 |
| `inputs.env.sh` | `$CASE/short-rna/inputs.env.sh` | RNA 样本路径（每病例） |
| `case.config.sh` | `$CASE/case.config.sh` | **通用化新增**：DNA+RNA 统一样本配置 |
| `tools.env.sh` | `$NEOAG_ROOT/conf/tools.env.sh` | na neo 工具路径（production 用） |

---

## 4. 非代码依赖（refs / indexes）

### 4.1 neoag-basic-tools-install-deps

根：`/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/`

| 类别 | 路径 |
|---|---|
| hg38 FASTA | `refs/hg38/Homo_sapiens_assembly38.fasta` |
| Sequenza chr FASTA | `refs/sequenza/reference/GRCh38.primary_assembly.chr.fa` |
| HLA-LA graph | `refs/hla/PRG_MHC_GRCh38_withIMGT/` |
| HMF Purple refs | `refs/hmf/purple_reference/` |
| LOHHLA polysolver | `refs/lohhla/polysolver/` |
| EasyFuse / VEP / SNAF refs | `refs/easyfuse/`, `refs/vep/`, `refs/snaf/` |
| 工具二进制 | `tools/neodata_tools/`, `tools/sequenza/`, `tools/lohhla/` |

### 4.2 neodata4git（RNA / 预测器，共享只读）

根：`/mnt/zjl-bgi-zzb/peixunban/gl/liup/neodata4git`

| 类别 | 路径 |
|---|---|
| CTAT / STAR index | `data/ref/ctat/current/ctat_genome_lib_build_dir` |
| Salmon / RSEM | `data/rna/gencode_v49/` |
| VEP cache | `data/vep/` |
| EasyFuse / FusionCatcher | `data/easyfuse/current/` |
| 预测器 | `data/predictors/{netMHCpan,prime,bigmhc,DeepImmuno,netchop}/` |

---

## 5. Conda 环境（134 `/home/na/miniforge3/envs/`）

| 环境 | 用途 | Python | 备注 |
|---|---|---|---|
| `neoag-pvactools711` | pVACseq / fuse / splice | 3.11.15 | **生产优先**；禁用 TF_USE_LEGACY_KERAS |
| `neoag-vep` | VEP Perl 隔离 | 3.12.13 | |
| `neoag-fusion` | STAR / Arriba / Salmon | 3.14.0 | R 4.3.3 |
| `neoag-sequenza` | Sequenza pileup/fit | 3.10.20 | R 4.2.3 |
| `neoag-ascat` | ASCAT fit | 3.14.6 | R 4.0.5 |
| `neoag-gatk` | GATK / picard | 3.10.20 | 含 picard-3.5.0 |
| `neoag-optitype` | OptiType | 3.13.13 | |
| `neoag-facets` | FACETS | — | R 4.5.3 |
| `neoag-snaf` | SNAF | 3.8.20 | |
| `neoag-splicemutr` | SpliceMutr | 3.11.15 | |
| `neoag-samtools19` | Sequenza mpileup | — | samtools **1.9** |
| `neoag-tools` | 通用工具 | 3.11.15 | ⚠️ 含 stub samtools 0.1.19，勿上 PATH |

HMFTOOLS：在 deps `tools/neodata_tools/HMFTOOLS/.conda`（非 NEOAG_ROOT 内）

---

## 6. 三机对比（2026-08-23）

| 项目 | 134 ✅ | 66 ⚠️ | 169 ❌ |
|---|---|---|---|
| NEOAG_ROOT (na0707) | `/home/na/.../na0707_sync_20260811` | `/root/neo/src/na0707_upload_release`（切片） | 同 66 |
| CONDA_BASE | `/home/na/miniforge3` (29 envs) | `/root/neo/envs/miniforge3` (17 envs) | **无** |
| neoag-ascat | ASCAT_OK | **R 包损坏** | MISSING |
| neoag-gatk picard | ✅ 3.5.0 | **MISSING** | MISSING |
| HMFTOOLS (deps) | ✅ | ✅ | ✅ |
| shared_scripts sequenza | `283de1b` 金路径 | 同左 | 同左 |
| 病例 scripts 同步 | sunbinbin=shared | jinganxin **Sequenza 旧版** | 未审计 |

### 66 待修复

1. `neoag-ascat`：重装或从 134 rsync env
2. `neoag-gatk`：补 `picard.jar` 或改 `run_lohhla.sh` 搜 deps 内 picard
3. `run_purple_steps.sh`：amber 改走 deps HMFTOOLS（非 NEOAG_ROOT）
4. 病例 `run_sequenza_steps.sh` 同步金路径 `shared_scripts/sequenza/`

### 169 待修复

1. 运行 `neoag-basic-tools-install/scripts/install.sh --one-shot` 安装全部 conda env
2. 同步 na0707 或挂载 134 NEOAG_ROOT

---

## 7. 硬编码路径（须参数化）

| 类别 | 示例 | 通用化方案 |
|---|---|---|
| 134 neo 路径 | `/home/na/project/neoantigen/...` | `bootstrap_case.sh` + `lib_portable_env.sh` |
| 134 conda | `/home/na/miniforge3` | `neoag_resolve_conda_base()` |
| 66 neo | `/root/neo/src/na0707_upload_release` | 同上 |
| deps 根 | `/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps` | `NEOAG_BASIC_DEPS_DIR` |
| neodata | `/mnt/zjl-bgi-zzb/.../neodata4git` | `NEODATA_ROOT` in config |
| sunbinbin 样本 BAM/VCF | zjl 路径 | `case.config.sh` 必填 |
| TMPDIR | `/tmp` | 强制 `$CASE_ROOT/tmp` |

---

## 8. 与通用化交付物关系

| 交付物 | 路径 |
|---|---|
| 通用流水线 | `/mnt/neoag_100T/majiaxin/neoag-universal-pipeline/` |
| 配置模板 | `config/case.config.sh.template` |
| 病例脚手架 | `scripts/bootstrap_case_dir.sh` |
| 一键总控 | `scripts/run_case_all.sh` |
| 部署手册 | `docs/universal-pipeline-deployment-manual.md` |
