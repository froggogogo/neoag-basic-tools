# 内网 NeoAg 运行手册（66 / 134 / 169）

> 本文档说明在三台内网计算机上如何运行 DSRCT 等新抗原基础分析流程。  
> **运行时只用 NAS 上的 `shared_scripts` 与各病例目录下的 wrapper 脚本**，不依赖 git 仓库里的 `neoag-basic-tools-run` skill（该 skill 是面向外部安装的产品，不在三机上执行）。

**文档位置（NAS，三机可读）**：

```text
/mnt/zzbnew/peixunban/gl/mjx/neoag/docs/intranet-neoag-runbook.md
```

**共享脚本根目录**：

```text
/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts/
```

---

## 1. 三台机器

| 主机 | 内网 IP | 典型用途 |
|------|---------|----------|
| 66 | 10.200.65.66 | RNA、部分 DNA/HLA；EasyFuse 需 Ubuntu 22.04 |
| 134 | 10.200.50.134 | 大 WGS、Sequenza pileup/fit、production |
| 169 | 10.200.65.169 | 与 66/134 共用 NAS 路径，按负载选用 |

- 数据与脚本均在 **`/mnt/zzbnew`**（及 `/mnt/neoag_100T` 原始 BAM/FASTQ）上，三机挂载同一套路径。
- 登录：SSH 密钥（勿在文档/聊天中写密码）。本机可用 Cursor `cross-server-access` / `cs.py`。
- 跑任务前看负载：`uptime` 或 `awk '{print $1}' /proc/loadavg`，大任务尽量错开 Sequenza、STAR、HLA 同时满负载。

---

## 2. 概念：三层结构

```
┌─────────────────────────────────────────────────────────┐
│  shared_scripts（NAS 母版，所有病例共用）                  │
│  case_templates / short_rna_templates / sequenza / …     │
└───────────────────────────┬─────────────────────────────┘
                            │ rsync 复制（新病例做一次）
                            ▼
┌─────────────────────────────────────────────────────────┐
│  病例目录 wrapper（每个样本自己的 run_*.sh）               │
│  $CASE/scripts/  +  $CASE/short-rna/scripts/             │
└───────────────────────────┬─────────────────────────────┘
                            │ bash wrapper
                            ▼
┌─────────────────────────────────────────────────────────┐
│  已安装工具（conda / neoag-basic-tools-install-deps）     │
│  OptiType, STAR, Sequenza, pVACtools, SNAF, …            │
└─────────────────────────────────────────────────────────┘
```

- **Wrapper**：只负责读配置、调工具、写 log、打 `.done`，不是算法本身。
- **母版更新**：开发侧改 sunbinbin 金路径后，用 `sync_shared_scripts.py` 同步到 `shared_scripts`（见 §8）。

---

## 3. NAS 目录结构

### 3.1 共享脚本（所有同事复制来源）

```text
/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts/
├── README.md
├── case_templates/              # DNA：HLA、CNV、LOHHLA、VEP、pVACseq、sliding …
│   ├── lib_portable_env.sh      # 按 66/134/169 解析 NEOAG_ROOT（勿写死 134 路径）
│   ├── lib_site_defaults.sh
│   ├── lib_tool_timing.sh
│   ├── run_hla_all.sh
│   ├── run_cnv_hla_parallel.sh
│   ├── run_cnv_all.sh
│   ├── run_lohhla.sh
│   ├── run_dna_downstream_parallel.sh
│   ├── run_dna_all.sh
│   ├── run_sequenza_steps.sh    # 也可改用 sequenza/ 下带 per-chrom bin 的版本
│   └── …
├── short_rna_templates/         # RNA 逐步工具 + 模板配置
│   ├── inputs.env.sh.template   # 复制为病例 short-rna/inputs.env.sh 后改样本区
│   ├── run_short_rna_all.sh     # RNA 总控（多 wave 并行/串行）
│   ├── run_star.sh
│   ├── run_salmon.sh
│   ├── run_easyfuse.sh
│   ├── run_pvacfuse.sh
│   ├── run_pvacsplice.sh
│   └── …
├── sequenza/                    # Sequenza 金路径（NUL-safe bam2seqz + 按染色体 bin + R fit）
│   ├── run_sequenza_steps.sh
│   ├── bam2seqz_nulsafe.py
│   └── run_sequenza_fit.R
├── snaf/
│   └── run_snaf_pipeline.sh
├── splicemutr/
│   └── run_splicemutr_patient.sh
└── rna/
    └── run_short_rna_master.sh  # 可选：与 short_rna_templates 编排类似
```

### 3.2 单个病例目录（以 sunbinbin 为例）

```text
/mnt/zzbnew/peixunban/gl/mjx/neoag/<PATIENT_ID>/
├── scripts/                     # DNA wrapper（从 case_templates 复制）
├── short-rna/
│   ├── scripts/                 # RNA wrapper（从 short_rna_templates 复制）
│   ├── inputs.env.sh            # 本病例 FASTQ、工具路径、HLA 文件指针
│   ├── star/  salmon/  snaf/  … # 各工具输出
│   └── evidence/                # RNA 证据 handoff
├── hla/                         # HLA 分型 + hla_consensus.txt
├── facets/  sequenza/  purple/  ascat/   # CNV / 纯度
├── lohhla/
├── vep/  pvacseq/  sliding/
├── somatic/  evidence/
├── logs/
├── tmp/                         # 临时文件必须放病例下，勿用根分区 /tmp
└── run_<patient>_all.sh         # 可选：病例一键总控（自行维护或 agent 生成）
```

### 3.3 中央依赖（安装产物，三机共用）

```text
/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/
├── configs/site.env.sh          # source 后解析 conda、REF、VEP cache 等
├── configs/bootstrap_case.sh
├── refs/                        # hg38 chr、HLA、Sequenza GC …
├── tools/sequenza/              # 与 shared_scripts/sequenza 同步的 runner
└── software/miniforge3/         # 部分机器 conda 在 /root/neo/envs/miniforge3 或 /home/na/miniforge3
```

原始测序数据常见路径：

```text
/mnt/neoag_100T/data/DSRCT/<patient>/...
```

---

## 4. 新病例准备（首次）

在**任意一台能写 zzbnew 的机器**上执行（把 `MYSAMPLE` 换成样本 ID）：

```bash
SHARED=/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts
CASE=/mnt/zzbnew/peixunban/gl/mjx/neoag/MYSAMPLE
DEPS=/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps

mkdir -p "$CASE"/{scripts,short-rna/scripts,logs,tmp}

# 复制 wrapper 母版
rsync -a "$SHARED/case_templates/"       "$CASE/scripts/"
rsync -a "$SHARED/short_rna_templates/"  "$CASE/short-rna/scripts/"
cp "$SHARED/short_rna_templates/inputs.env.sh.template" \
   "$CASE/short-rna/inputs.env.sh"

# 可选：加载中央依赖环境（交互 shell 调试用）
source "$DEPS/configs/site.env.sh"
```

编辑 **`$CASE/short-rna/inputs.env.sh`** 顶部样本区：

- `PATIENT_ID`
- `RNA_FASTQ1` / `RNA_FASTQ2`（无 RNA 可留空，后面跳过 RNA wrapper）
- 必要时改 `NEODATA_ROOT`、索引路径（多数情况 bootstrap 已够）

**DNA 运行前必须 export（或在总控脚本里写死）**：

```bash
export PATIENT_ID=MYSAMPLE
export CASE_ROOT="$CASE"
export TUMOR_BAM=/path/to/tumor.bam
export NORMAL_BAM=/path/to/normal.bam
export SOMATIC_VCF=/path/to/somatic.pass.vcf.gz   # 可为空则跳过 somatic 下游
```

勿依赖脚本里旧的 sunbinbin 默认 zjl 路径；未 export 时新版本会直接报错。

确认 BAM 有 `.bai`，VCF 有 `.tbi`（没有则 `samtools index` / `tabix`）。

---

## 5. 流程概览（跑什么、顺序）

### 5.1 全链路（肿瘤 WGS + 血液 WGS + bulk RNA）

```text
[HLA 队列]  OptiType → SpecHLA → HLA-LA → consensus
     ∥（可与 HLA 并行，看机器）
[CNV 队列]  FACETS → Sequenza → PURPLE → ASCAT → purity handoff

[LOHHLA]    依赖 HLA consensus + CNV 纯度

[RNA]       Salmon → (STAR ∥ STAR-Fusion) → Arriba ∥ RegTools → EasyFuse → RSEM
            → cis-splice → RNA VEP → pVACfuse ∥ pVACsplice → evidence

[SNAF]      依赖 STAR BAM + SJ.out.tab + HLA consensus
[SpliceMutr] 依赖 SNAF

[DNA 下游]  somatic handoff → VEP → pVACseq ∥ sliding → DNA evidence

[production] 仅在有完整 neo 仓库且用户明确要求时单独跑（默认不在「基础工具链」内）
```

### 5.2 RNA-only 病例

跳过 HLA/CNV/LOHHLA/pVACseq/sliding（或仅跑 RNA 相关）；无 HLA 时 pVACfuse/pVACsplice/SNAF 无法跑。

### 5.3 并行建议

| 场景 | 建议 |
|------|------|
| HLA + CNV | `run_cnv_hla_parallel.sh` 内建两队列 |
| RNA Wave1 | STAR 与 STAR-Fusion 后台并行（见 `run_short_rna_all.sh`） |
| Sequenza | 按染色体 pileup，`CHUNK_JOBS=2`；**不要**对合并后的 20G raw seqz 整体 binning（用 `sequenza/run_sequenza_steps.sh` per-chrom bin 版） |
| 三机分工 | 例如 134 跑 Sequenza，66 跑 RNA，避免同机抢满 20 核 |

---

## 6. 如何运行

### 6.1 分步运行（推荐熟悉流程时）

SSH 到目标机后：

```bash
CASE=/mnt/zzbnew/peixunban/gl/mjx/neoag/MYSAMPLE
export PATIENT_ID=MYSAMPLE CASE_ROOT="$CASE"
export TUMOR_BAM=... NORMAL_BAM=... SOMATIC_VCF=...
export TMPDIR="$CASE/tmp" TMP="$TMPDIR" TEMP="$TMPDIR"

# DNA
bash "$CASE/scripts/run_hla_all.sh"
bash "$CASE/scripts/run_cnv_hla_parallel.sh"    # 或 RUN_HLA=0 / RUN_CNV=1 单独跑
bash "$CASE/scripts/run_lohhla.sh"
bash "$CASE/scripts/run_dna_downstream_parallel.sh"

# RNA
bash "$CASE/short-rna/scripts/run_short_rna_all.sh"
# 或 STAGE=from_wave2 等续跑

# SNAF + SpliceMutr（也可被 short-rna 总控或单独队列调用）
bash "$SHARED/snaf/run_snaf_pipeline.sh" --bam ... --hla-file "$CASE/hla/hla_consensus.txt" ...
export SAMPLE=... WORK=... SNAF_RESULT=... HLAS=...
bash "$SHARED/splicemutr/run_splicemutr_patient.sh"
```

### 6.2 一键运行（病例总控脚本）

部分病例有 **`run_<patient>_all.sh`**（如 jinganxin），内部按顺序调用上述 wrapper，并带 `STAGE=` 续跑。新建病例可抄 sunbinbin / jinganxin 总控改路径。

后台示例：

```bash
LOG="$CASE/logs/nohup_all_$(date +%Y%m%d_%H%M%S).log"
nohup env STAGE=all CONTINUE_ON_ERROR=1 \
  bash "$CASE/run_mysample_all.sh" > "$LOG" 2>&1 &
echo $! > "$CASE/logs/all.pid"
tail -f "$LOG"
```

### 6.3 常用环境变量

| 变量 | 含义 |
|------|------|
| `PATIENT_ID` | 样本 ID |
| `CASE_ROOT` | 病例根目录 |
| `TUMOR_BAM` / `NORMAL_BAM` | WGS BAM |
| `SOMATIC_VCF` | 体细胞 PASS VCF |
| `FORCE=1` | 忽略已有 `.done` 重跑 |
| `CONTINUE_ON_ERROR=1` | 某步失败继续后续（默认建议开启） |
| `STAGE=` | 总控脚本分段：如 `hla`、`cnv`、`from_wave2` |
| `SEQUENZA_STEP=pileup\|fit\|all` | Sequenza 分段 |
| `CHUNK_JOBS=2` | Sequenza 染色体并行数 |

---

## 7. 完成标志与结果路径

| 步骤 | 典型 marker / 产物 |
|------|-------------------|
| HLA | `hla/hla_consensus.txt`, `hla/.hla_consensus.done` |
| Sequenza | `sequenza/.pileup.done`, `sequenza/.fit.done`, `sequenza_fit/*.sequenza_summary.tsv` |
| FACETS | `facets/.../purity.tsv` |
| LOHHLA | `lohhla/.lohhla.done` |
| STAR | `short-rna/star/.star.done`, `Aligned.sortedByCoord.out.bam` |
| SNAF | `short-rna/snaf/.snaf.done`, `snaf_candidates.tsv` |
| SpliceMutr | `short-rna/splicemutr/.splicemutr_patient_complete` |
| pVACseq | `pvacseq/.pvacseq.done` |
| RNA evidence | `short-rna/evidence/` |
| DNA evidence | `evidence/` |

参考完整病例：**sunbinbin**（金标准，表格与路径最全）。

---

## 8. 监控、续跑、排错

**看是否在跑**

```bash
ps -ef | grep -E 'MYSAMPLE|run_hla|sequenza|STAR' | grep -v grep
tail -f "$CASE/logs/"*.log
```

**续跑原则**

1. 看哪一步没有 `.done` 或 log 里最后 ERROR。
2. 只重跑失败 stage；已完成的不要 `FORCE=1` 除非确需覆盖。
3. Sequenza：pileup 已有 `chrom/*.seqz.gz` 时会 reuse；binning 失败用 **per-chrom bin** 版 runner 从 `SEQUENZA_STEP=pileup` 或 `fit` 续跑。
4. RNA：`run_short_rna_all.sh` 支持从中间 wave 续跑（视病例总控是否实现 `STAGE=`）。

**常见问题**

| 现象 | 处理 |
|------|------|
| `tools.env.sh: No such file` | 未用 portable env；确保 wrapper 含 `lib_portable_env.sh`，或 `source $DEPS/configs/bootstrap_case.sh` |
| Sequenza `too many values to unpack (expected 14)` | 合并 raw chrom seqz 再 binning；改用 `shared_scripts/sequenza/run_sequenza_steps.sh` |
| EasyFuse 失败 | 仅 Ubuntu 22.04；134 若为 20.04 则 RNA 融合用 66 |
| pVAC 失败 TF/Keras | 勿 `TF_USE_LEGACY_KERAS=1`；用 `neoag-pvactools711` 环境 |
| 磁盘满 | 临时目录必须在 `$CASE/tmp`，勿写 `/tmp` |

---

## 9. 与 git「运行 skill」的区别

| | 内网三机（本文） | neoag-basic-tools-run（git 产品） |
|--|------------------|-------------------------------------|
| 用途 | 实验室 DSRCT 等生产任务 | 给外部用户安装、一键部署 |
| 入口 | `$CASE/scripts/run_*.sh` + NAS `shared_scripts` | `run.sh` + stages |
| 是否在三机跑 skill | **否** | 否（skill 不在三机 runtime） |

开发侧若更新了 sunbinbin 金路径，在开发机执行同步（需能写 zzbnew + neoag_100T deps）：

```bash
# 脚本在 neoag-skills 仓库
python3 neoag-basic-tools-run/scripts/sync_shared_scripts.py
# 或将 skill 内文件 scp 到 66:/tmp/neoag_sync/ 后在 NAS 上执行
```

同步后新病例 `rsync` 最新 `case_templates` / `short_rna_templates` 即可；已跑完病例不必覆盖 wrapper，除非要修 bug。

---

## 10. 给 AI / 同事的一句话任务模板

```text
在 [66/134/169] 跑病例 [ID]，不要用 neoag-basic-tools-run skill。
NAS：/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts
病例：/mnt/zzbnew/peixunban/gl/mjx/neoag/[ID]
若无 wrapper 则从 shared_scripts 复制；export BAM/VCF/FASTQ；
bash scripts/run_hla_all.sh、run_cnv_hla_parallel.sh、short-rna/run_short_rna_all.sh 等。
不要 production；汇报 .done 与 logs。
```

---

## 11. 参考路径速查

| 内容 | 路径 |
|------|------|
| 本文档 | `/mnt/zzbnew/peixunban/gl/mjx/neoag/docs/intranet-neoag-runbook.md` |
| 共享脚本 | `/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts/` |
| 病例根 | `/mnt/zzbnew/peixunban/gl/mjx/neoag/<PATIENT_ID>/` |
| 金标准病例 | `/mnt/zzbnew/peixunban/gl/mjx/neoag/sunbinbin/` |
| 中央 deps | `/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/` |
| 原始数据 | `/mnt/neoag_100T/data/DSRCT/...` |

---

*文档版本：2026-08-20。如有流程变更，请更新本文并重新 sync shared_scripts。*
