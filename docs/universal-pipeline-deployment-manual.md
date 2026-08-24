# NeoAg 通用化部署手册

> 版本：2026-08-23  
> 金标准：134 `sunbinbin` 病例 + `shared_scripts/`  
> 通用流水线：`/mnt/neoag_100T/majiaxin/neoag-universal-pipeline/`

---

## 1. 目标

**换病人只改 `case.config.sh` 中的样本路径**，其余脚本、环境、参考数据不变。

---

## 2. 环境准备

### 2.1 三机前提

- 能挂载 `neoag_100T` 与 `zzbnew` NAS
- 能只读访问 `zjl-bgi-zzb`（neodata4git RNA refs）

### 2.2 安装 deps（每台机器执行一次）

```bash
cd /path/to/neoag-skills/neoag-basic-tools-install/scripts
bash install.sh --one-shot --deps-dir /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps
bash ensure_host_runtime.sh
bash host_verify.sh
```

### 2.3 134 金标准 env（参考）

134 使用 `/home/na/miniforge3` 下 29 个 `neoag-*` env。  
66 / 169 须与 134 **同名同版本**；当前缺口见 `docs/gold-standard-inventory-134.md` §6。

**66（2026-08-23/24 已同步）：** `host_verify` 全 OK；`neoag-ascat` / `neoag-gatk`/picard / HMFTOOLS 可用。  
勿用 rsync 直接拷贝 134 conda env（会留下 `/home/na/miniforge3/...` 硬编码）。正确做法：

```bash
# 在目标机上：从 conda-pack 解包并用本机 python 跑 conda-unpack
PACK=$DEPS/packages/conda_packs/neoag-ascat.tar.gz
DEST=$CONDA_BASE/envs/neoag-ascat
rm -rf "$DEST" && mkdir -p "$DEST"
tar -xzf "$PACK" -C "$DEST"
$CONDA_BASE/bin/python "$DEST/bin/conda-unpack"
"$DEST/bin/Rscript" -e 'library(ASCAT); cat("ASCAT_OK\n")'
# 或：bash scripts/ensure_host_runtime.sh  （已含 ensure_ascat）
```

**169：** 暂缓；需完整执行 `install.sh --one-shot`（当前无 conda env）。

### 2.4 同步 shared_scripts

在能写 NAS 的机器上：

```bash
python3 neoag-skills/neoag-basic-tools-run/scripts/sync_shared_scripts.py
```

---

## 3. 新病例准备

### 3.1 编辑配置

```bash
# 1. 复制模板
cp /mnt/neoag_100T/majiaxin/neoag-universal-pipeline/config/case.config.sh.template \
   /mnt/zzbnew/peixunban/gl/mjx/neoag/MY_PATIENT/case.config.sh

# 2. 只改样本区
vim .../MY_PATIENT/case.config.sh
```

**必填字段：**

| 字段 | 说明 |
|---|---|
| `PATIENT_ID` | 病例 ID |
| `TUMOR_BAM` | WGS tumor BAM（含 .bai） |
| `NORMAL_BAM` | WGS normal/blood BAM |
| `SOMATIC_VCF` | 预计算 PASS somatic VCF（DNA 下游需要） |
| `RNA_FASTQ1/2` | 有 RNA 时填写 |
| `CASE_ROOT` | 默认 `.../neoag/${PATIENT_ID}` |

### 3.2 初始化目录

```bash
bash /mnt/neoag_100T/majiaxin/neoag-universal-pipeline/scripts/bootstrap_case_dir.sh \
  /mnt/zzbnew/peixunban/gl/mjx/neoag/MY_PATIENT/case.config.sh
```

会 rsync `shared_scripts` 到 `$CASE/scripts/`，并强制覆盖 Sequenza 金路径脚本。

### 3.3 RNA 配置（可选）

编辑 `$CASE/short-rna/inputs.env.sh`（从 template 生成），填 FASTQ 与 index 路径。  
工具路径通常由 `bootstrap_case.sh` 自动解析，无需手改。

---

## 4. 运行

```bash
cd /mnt/zzbnew/peixunban/gl/mjx/neoag/MY_PATIENT
nohup bash run_case_all.sh > logs/nohup_case_all.log 2>&1 &
```

**分阶段：**

```bash
STAGE=dna_prereq   bash run_case_all.sh   # CNV||HLA + LOHHLA
STAGE=dna_downstream bash run_case_all.sh
STAGE=rna          bash run_case_all.sh
STAGE=snaf         bash run_case_all.sh
STAGE=splicemutr   bash run_case_all.sh
RUN_PRODUCTION=1 STAGE=production bash run_case_all.sh  # 可选
```

**续跑：** 各子脚本有 `.done` marker，直接重跑即可跳过已完成步骤。

---

## 5. 验证清单（E2E）

- [ ] `hla/.hla_consensus.done` + `hla/hla_consensus.txt`
- [ ] `facets/.../purity.tsv` 或 `evidence/purity.tsv`
- [ ] `sequenza/.fit.done` + `sequenza_fit/*_summary.tsv`
- [ ] `lohhla/.lohhla.done`
- [ ] `vep/.vep.done` + `pvacseq/.pvacseq.done`
- [ ] `short-rna/star/.star.done`（如有 RNA）
- [ ] `short-rna/snaf/.snaf.done` + `splicemutr/.splicemutr_patient_complete`

---

## 6. 常见问题

### Sequenza merge 中断

- 检查 `yumin.merged.seqz.gz.tmp` 是否不完整；删除 tmp 后 `SEQUENZA_STEP=pileup` 续跑
- 确保用 `shared_scripts/sequenza/run_sequenza_steps.sh`（md5 `283de1b`），非旧 per-chrom bin 版

### LOHHLA picard.jar not found（66）

- 补 `neoag-gatk` 内 picard，或扩展 `run_lohhla.sh` 搜索 `deps/tools/neodata_tools/.../picard.jar`

### PURPLE AMBER conda prefix missing

- `amber` 应走 `deps/tools/neodata_tools/HMFTOOLS/.conda`，非 `NEOAG_ROOT/tools/HMFTOOLS`

### ASCAT Rscript execution error（66）

- 根因：直接 tar/rsync 134 env 后，`bin/R` 仍指向 `/home/na/miniforge3/...`
- 修复：用 `conda_packs/neoag-ascat.tar.gz` 解包 + `$CONDA_BASE/bin/python …/conda-unpack`（见 §2.3）

### TMPDIR 必须在 CASE_ROOT

- 根分区 `/` 空间小；`case.config.sh` 已设 `TMPDIR=$CASE_ROOT/tmp`

### pVAC 711 失败

- 禁止 `export TF_USE_LEGACY_KERAS=1`；`bootstrap_case.sh` 会自动 unset

---

## 7. 目录布局（neoag-100T）

```text
/mnt/neoag_100T/majiaxin/
├── neoag-basic-tools-install-deps/   # refs + tools + site.env
└── neoag-universal-pipeline/         # 本手册对应流水线
    ├── config/case.config.sh.template
    ├── scripts/
    │   ├── run_case_all.sh
    │   ├── bootstrap_case_dir.sh
    │   └── lib/load_config.sh
    └── README.md
```

病例数据与结果仍在 `zzbnew/.../neoag/$PATIENT_ID/`。
