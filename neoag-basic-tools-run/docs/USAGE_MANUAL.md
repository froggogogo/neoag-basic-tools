# 人工一键运行

## 1. 环境

```bash
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
cd /path/to/neoag-basic-tools-install/neoag-basic-tools-run
```

若尚未安装 deps，先按上级目录 [docs/USAGE_MANUAL.md](../../docs/USAGE_MANUAL.md) 安装。

## 2. 探查机器

```bash
bash scripts/probe_host.sh
# JSON: bash scripts/probe_host.sh --json
```

## 3. 准备病例

推荐模板：`/mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin`

至少需要：

- `scripts/run_cnv_hla_parallel_<sample>.sh`（或拆分 HLA/CNV 脚本）
- `short-rna/scripts/run_short_rna_all_<sample>.sh`
- `short-rna/inputs.env.sh`（FASTQ、refs）

可选：`run_lohhla_*`、`run_snaf_*`、`run_splicemutr_patient_*`、`run_vep_somatic_*`

## 4. 预览

```bash
bash scripts/run.sh --mode plan --yes \
  --case-root /mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin \
  --sample-id sunbinbin \
  --neo-root /home/na/project/neoantigen/neoag_event_pipeline_na0707_sync_20260811
```

## 5. 运行

```bash
bash scripts/run.sh --yes \
  --case-root /mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin \
  --sample-id sunbinbin \
  --neo-root /path/to/full/neo \
  --tumor-bam /path/to/tumor.bam \
  --normal-bam /path/to/normal.bam \
  --somatic-vcf /path/to/somatic.pass.vcf.gz \
  --rna-r1 /path/to/R1.fq.gz \
  --rna-r2 /path/to/R2.fq.gz
```

只跑基础工具、跳过生产：

```bash
bash scripts/run.sh --yes --skip-production ...
```

强制串行（小机器或调试）：

```bash
bash scripts/run.sh --yes --sched serial ...
```

## 6. 看结果

```bash
ls -la $CASE_ROOT/production_from_results_manifest_*/final/reports/
tail -100 $CASE_ROOT/logs/run_*.log
```

## 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `CONTINUE_ON_ERROR` | 1 | 单步失败继续 |
| `FORCE` | 0 | 忽略 done 标记 |
| `MIN_DUAL_NPROC` | 12 | dual 阈值 |
| `MIN_DUAL_MEM_GB` | 48 | dual 阈值 |
| `MIN_FULL_NPROC` | 20 | full 阈值 |
| `MIN_FULL_MEM_GB` | 96 | full 阈值 |
