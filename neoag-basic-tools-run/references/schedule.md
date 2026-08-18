# schedule.md — 并行调度

参考 sunbinbin（~20 核 / ~235G RAM）在 66 上的实际跑法。

## 主机探查

`scripts/probe_host.sh` 读取：

- `nproc` / `MemTotal` / `MemAvailable` / load1
- Ubuntu 22.04 → `easyfuse_os=1`

## 三档模式

### serial

- 条件：`nproc < 12` **或** `mem_gb < 48`
- 顺序：HLA → CNV → RNA → LOHHLA → SNAF → SpliceMutr → VEP → production

### dual

- 条件：`nproc ≥ 12` 且 `mem_gb ≥ 48`
- Wave A（并行）：HLA 队列 ∥ CNV 队列
- Wave B：RNA master（内部仍分 wave1/2/3）
- 然后串行：LOHHLA → SNAF → SpliceMutr → VEP → production

### full

- 条件：`nproc ≥ 20` 且 `mem_gb ≥ 96`
- Wave A（并行）：HLA ∥ CNV ∥ RNA（内置 master：Salmon → EasyFuse）
- 然后：LOHHLA → SNAF → SpliceMutr → VEP → production

## 队列内部（始终串行）

### CNV

FACETS → **Sequenza（内置 gold runner）** → PURPLE → ASCAT  

Sequenza 不依赖病例旧 `run_sequenza_fit.R`：

1. `bam2seqz_nulsafe.py` + samtools 1.9（避免 1.23 NUL）
2. merge + `seqz_binning`（`.small.seqz.gz` 可能是明文 TSV）
3. chrom-split fread fit → `sequenza_fit/${sample}.sequenza_summary.tsv`

产物：`evidence/purity.tsv`、`evidence/cnv_segments.tsv`、`sequenza/.fit.done`

### HLA

OptiType → SpecHLA → HLA-LA → consensus  
产物：`hla/hla_consensus.txt`

### RNA（内置 EasyFuse-centric master）

- Wave1：Salmon（定量，skip-if-done）
- Wave2：**EasyFuse**（融合 meta；内部含 STAR / Arriba / STAR-Fusion / FusionCatcher，**不再单独跑**）
- Wave2b：`harvest_easyfuse_artifacts`（从 EasyFuse work 链接 STAR BAM / Arriba 等供下游）
- Wave3 串行：RegTools → RSEM
- 然后：pVACfuse、pVACsplice、evidence 汇总

病例仍提供 per-tool wrapper（`run_salmon_*`、`run_easyfuse_*`、`run_regtools_*` 等）；不再要求 `run_star_*` / `run_arriba_*` / `run_star_fusion_*` / `run_fusioncatcher_*`。

## 依赖边

```text
HLA ──────────────┬──→ LOHHLA
CNV (purity) ─────┘
HLA + junctions ──→ SNAF → SpliceMutr
somatic VCF ──────→ VEP → production
all evidence ─────→ production
```

## 资源提示（sunbinbin 默认）

| 侧 | 参数示例 |
|----|----------|
| CNV | CHUNK_JOBS=2, HMF_THREADS=4, JVM -Xmx24g |
| HLA | OptiType 8, SpecHLA 8, HLA-LA 6 |
| RNA | EasyFuse（内部并行）, CAP_LOAD=18 |

病例 wrapper 内可覆盖；run skill 不硬编码线程数。
