# sunbinbin-map — 参考病例与 wrapper 映射

Gold case（最完整）：

```text
/mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin
```

## 关键脚本 → run skill stage

| sunbinbin 脚本 | stage | 说明 |
|----------------|-------|------|
| `scripts/run_cnv_hla_parallel_sunbinbin.sh` | hla + cnv | `RUN_CNV=0 RUN_HLA=1` 或反之可拆分 |
| `scripts/run_sequenza_steps.sh` | sequenza | 运行 skill **优先用** `$DEPS_DIR/tools/sequenza/` 的 gold 副本（chrom-split fit + NUL-safe bam2seqz）；病例脚本仅作 fallback |
| `scripts/run_lohhla_sunbinbin.sh` | lohhla | 需 HLA + purity |
| 内置 `run_short_rna_master` + per-tool `run_star_*` / `run_arriba_*` / `run_star_fusion_*` / `run_easyfuse_*` | rna | STAR∥SF → Arriba → EasyFuse（无独立 FC）→ pVAC* |
| `short-rna/scripts/run_snaf_*` / case snaf | snaf | junction → 候选 |
| `scripts/run_splicemutr_patient_*` | splicemutr | SNAF txt → NetMHCpan |
| `scripts/run_vep_somatic_*` | vep | somatic VCF 注释 |
| `production_from_results_manifest_*/run_production.sh` | production | manifest + runner |

run skill **dispatch** 规则：在 `$CASE_ROOT` 下找 `run_<stem>.sh` 或 `run_<stem>_${SAMPLE_ID}.sh`。

## 生产接口（PASS 2026-08-14）

```text
OUT=.../production_from_results_manifest_20260814
reports:
  $OUT/final/reports/evidence_report.patient.html
  $OUT/final/reports/evidence_report.technical.html
  $OUT/final/reports/evidence_report.html
```

run skill `stages/production.sh` 等价逻辑，但：

- normal refs / predictors 来自 `$DEPS_DIR/refs/normal`、`$DEPS_DIR/licenses/predictors`
- 不再硬编码 zjl/zzbnew asset 路径
- 跑前 `ensure_neo_production.sh`：neo `conf/tools.env.local.sh` 指到 **完整** BigMHC（含 `src/predict.py`）+ DeepImmuno + MixMHCpred；sarcoma profile `sources = prime, bigmhc_im, deepimmuno`，`use_iedb_fallback=true`（仅 NetMHCpan 失败兜底）
- MixMHCpred 随 PRIME `-mix` 跑，不是独立 provenance 工具

详见 [production-predictors.md](production-predictors.md)。

## 输入数据（sunbinbin 示例）

| 类型 | 典型路径 |
|------|----------|
| tumor BAM | `.../dsrct/sunbinbin/wgs/sunbinbin_tumor.align.bam` |
| normal BAM | `.../sunbinbin_blood.align.bam` |
| somatic VCF | `.../somatic-vcf/sunbinbin_tumor.somatic.pass.vcf.gz` |
| RNA FASTQ | `.../sunbinbin_short-bulkrna/tumor/..._1.fq.gz` |

新样本：改 `short-rna/inputs.env.sh` 顶部样本区 + wrapper 内默认 BAM/VCF。

## 三台机器

| 主机 | IP | 备注 |
|------|-----|------|
| 66 | 10.200.65.66 | sunbinbin 主要跑法参考 |
| 134 | 10.200.50.134 | 同上 deps + case |
| 169 | 10.200.65.169 | 同上 |

每台先 `probe_host.sh`，小规格机用 `--sched serial`。

## 复制到新病例

```bash
CASE=/mnt/zzbnew/.../neoag/NEW_SAMPLE
rsync -a sunbinbin/scripts/ "$CASE/scripts/"
rsync -a sunbinbin/short-rna/scripts/ "$CASE/short-rna/scripts/"
cp sunbinbin/short-rna/inputs.env.sh "$CASE/short-rna/"
# 编辑 PATIENT_ID、FASTQ、BAM 路径
```

然后：

```bash
bash scripts/run.sh --yes \
  --case-root "$CASE" --sample-id NEW_SAMPLE --neo-root ...
```
