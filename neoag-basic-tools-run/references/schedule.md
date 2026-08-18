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
- Wave A（并行）：HLA ∥ CNV ∥ RNA（Salmon + STAR∥STAR-Fusion → Arriba → EasyFuse）
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

### RNA（内置 master）

- Wave1 并行：Salmon + **STAR ∥ STAR-Fusion**（STAR BAM 给 RegTools/剪接；STAR-Fusion 原生表给 pVACfuse）
- Wave2 并行：**Arriba** ∥ RegTools（Arriba 原生表给 pVACfuse）
- Wave3 串行：**EasyFuse** → RSEM。FusionCatcher **不单独跑**（只在 EasyFuse 内）
- 然后：pVACfuse（Arriba + STAR-Fusion）、pVACsplice、evidence 汇总

病例需提供 `run_star_*`、`run_arriba_*`、`run_star_fusion_*`、`run_easyfuse_*`、`run_salmon_*`、`run_regtools_*`。**不需要** `run_fusioncatcher_*`。

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
| RNA | STAR 10, STAR-Fusion 8, EasyFuse, CAP_LOAD=18 |

病例 wrapper 内可覆盖；run skill 不硬编码线程数。
