# neoag-basic-tools-run

新抗原**基础工具一键运行** Skill，与 [neoag-basic-tools-install](../README.md) 同仓库。

版本 **1.1.0**。调度参考 **sunbinbin**（66/134/169 上最完整病例）。 Sequenza 使用 2026-08-17 跑通的 chrom-split + NUL-safe bam2seqz，不依赖病例自带旧 fit。

## 做什么

1. **探查机器**：核数、内存 → `serial` | `dual` | `full`
2. **跑基础工具**：HLA、CNV（含内置 Sequenza）、LOHHLA、短读 RNA、SNAF、SpliceMutr、VEP
3. **生产接口**：汇总证据 → `evidence_report*.html`

## 前置

| 项 | 说明 |
|----|------|
| deps | 已安装 `neoag-basic-tools-install-deps` 并 `source site.env.sh` |
| case | 病例目录含 sunbinbin 风格 wrapper（见 [references/sunbinbin-map.md](references/sunbinbin-map.md)） |
| neo | 生产阶段需要**完整 neo 仓库** `--neo-root` |

## 快速开始

```bash
cd neoag-basic-tools-run
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh

# 只看机器能开多少并行
bash scripts/probe_host.sh

# 预览 DAG（不写盘）
bash scripts/run.sh --mode plan --yes \
  --case-root /mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin \
  --sample-id sunbinbin \
  --neo-root /path/to/full/neo

# 一键运行
bash scripts/run.sh --yes \
  --case-root /mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin \
  --sample-id sunbinbin \
  --neo-root /path/to/full/neo \
  --tumor-bam /path/to/tumor.bam \
  --normal-bam /path/to/normal.bam \
  --somatic-vcf /path/to/somatic.vcf.gz \
  --rna-r1 /path/to/R1.fq.gz \
  --rna-r2 /path/to/R2.fq.gz
```

## 并行策略

| mode | 条件（默认阈值） | 行为 |
|------|------------------|------|
| serial | &lt;12 核 或 &lt;48G | 全部串行 |
| dual | ≥12 核且 ≥48G | CNV 队列 ∥ HLA 队列；RNA 在 DNA 之后 |
| full | ≥20 核且 ≥96G | (CNV∥HLA) 与 RNA STAR 波同时开 |

队列**内部**仍串行（与 sunbinbin 一致）。详见 [references/schedule.md](references/schedule.md)。

## 主要参数

| 参数 | 说明 |
|------|------|
| `--case-root` | 病例根目录 |
| `--sample-id` | 样本 ID |
| `--deps-dir` | 默认 neoag_100T deps |
| `--neo-root` | 完整 neo（生产必需） |
| `--sched` | 强制 serial/dual/full |
| `--skip-production` | 只跑基础工具 |
| `--force` | 忽略 `.done` |
| `--mode probe\|plan\|run` | 探查 / 计划 / 运行 |

## Sequenza（内置）

CNV 队列会调用 `scripts/stages/sequenza.sh`：

- pileup：按染色体 `bam2seqz_nulsafe.py`（samtools **1.9**）→ merge → `seqz_binning`
- fit：chrom-split `fread`（`mmap=FALSE`），产物 `sequenza/sequenza_fit/*.sequenza_summary.tsv`
- 已有 `.fit.done` 则跳过；`--force` 重跑
- 优先 `$DEPS_DIR/tools/sequenza/run_sequenza_steps.sh`，否则用本 skill 自带副本

需要 `--tumor-bam` / `--normal-bam`（或病例 `run_sequenza_steps.sh`）。

## 产物

- 主日志：`$CASE_ROOT/logs/run_YYYYMMDD_HHMMSS.log`
- 生产输出：`$CASE_ROOT/production_from_results_manifest_YYYYMMDD/`
- 报告：`.../final/reports/evidence_report*.html`

## 文档

- [Agent 运行 Prompt](docs/USAGE_AGENT.md)
- [人工运行](docs/USAGE_MANUAL.md)
