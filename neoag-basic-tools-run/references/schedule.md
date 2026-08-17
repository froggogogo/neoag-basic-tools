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
- Wave A（并行）：HLA ∥ CNV ∥ RNA（RNA wrapper 自带 STAR∥STAR-Fusion 等）
- 然后：LOHHLA → SNAF → SpliceMutr → VEP → production

## 队列内部（始终串行）

### CNV

FACETS → Sequenza → PURPLE → ASCAT  
产物：`evidence/purity.tsv`、`evidence/cnv_segments.tsv`

### HLA

OptiType → SpecHLA → HLA-LA → consensus  
产物：`hla/hla_consensus.txt`

### RNA（short-rna wrapper）

- Wave1 并行：STAR ∥ STAR-Fusion（Salmon 可 skip-if-done）
- Wave2 并行：Arriba ∥ RegTools
- Wave3 串行：EasyFuse → FusionCatcher → RSEM
- 然后：pVACfuse、pVACsplice、evidence 汇总

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
| RNA | STAR 10, STAR-Fusion 8, CAP_LOAD=18 |

病例 wrapper 内可覆盖；run skill 不硬编码线程数。
