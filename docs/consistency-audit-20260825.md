# 环境与脚本一致性审计报告

> 日期：2026-08-25  
> 金标准：`sunbinbin` + `shared_scripts`（Sequenza 脚本对齐 `80cb04e4` 逻辑，假 .gz 兼容 β）  
> 范围：Sequenza / PURPLE / LOHHLA / SNAF 及编排入口

## 1. 审计总表

| 审计项 | sunbinbin（金标准） | jinganxin | yumin-tumor | 是否一致 | 修复动作 |
|--------|---------------------|-----------|-------------|----------|----------|
| Sequenza 脚本路径 | `scripts/run_sequenza_steps.sh`（病例本地历史成功） | 现经 `SHARED_SCRIPTS/sequenza/` | 同左 | **已对齐** | 改回 per-chrom bin→merge binned+awk；假 .gz 可接受 |
| Sequenza 流程 | per-chrom bin → merge binned | 同左（续跑中） | 同左（续跑中） | **已对齐** | 废弃 merge-raw→bin |
| HMFTOOLS conda | 134：`…/tools/HMFTOOLS/.conda`（~2.3G，含 amber） | 原缺失；wrapper 已改 DEPS 优先；`.conda` 正在 rsync→100T | 本机有 `.conda` | **进行中** | rsync→`neoag-100T/.../HMFTOOLS/.conda`；66 amber/cobalt/purple 动态探测 DEPS |
| LOHHLA `copyNumSolutions.txt` | FACETS purity + ASCAT ploidy 手写（README） | 曾缺；脚本可自动生成 | 已有 | **脚本已修** | `run_lohhla.sh` ensure_copynum（FACETS→ASCAT→Sequenza fallback） |
| mhcgnomes | 1.8.6；`Class2Pair` 在子模块未 re-export | 已 patch `__init__.py` | 已 patch | **已对齐** | `from .class2_pair import Class2Pair` |
| Python（neoag-snaf） | 3.8 | 3.8 | 3.8 | 是 | — |
| 编排启动方式 | 病例 `scripts/` 历史副本 | **`shared_tool` → SHARED_SCRIPTS** | 同左 | **已对齐** | `run_cnv_all.sh` 强制从通用脚本启动 |
| 中间产物命名 | `.pileup.done` / `.fit.done` / `*.small.seqz.gz` / `chrom_binned/` | 同约定 | 同约定 | 是 | — |
| CHUNK_JOBS / BIN_WINDOW | 默认 2 / 50 | 续跑 CHUNK_JOBS=4 | 同左 | 参数可配 | 与金默认兼容 |

## 2. Sequenza 根因（已修）

坏脚本「merge raw + `printf '\n'`、无 awk」在染色体交界插入空行 → `seqz_binning` `expected 14, got 1`。  
金路径：先 per-chrom bin，再 merge，并用 `awk 'NF==0{next} /^chromosome/{if(seen++) next}'`。

## 3. 验证状态（2026-08-25 续跑启动后）

| 样本 | Sequenza | PURPLE | LOHHLA | SNAF |
|------|----------|--------|--------|------|
| jinganxin (66) | **续跑中**（shared 金路径，reuse chrom→bin） | wrapper 已改；等 HMFTOOLS rsync 完成后可重跑 | 脚本可自动写 copyNum；待 Sequenza/确认 ASCAT 后触发 | mhcgnomes Class2Pair **已可 import**；待重跑 |
| yumin-tumor (134) | **续跑中** | 本机 env 本已可用 | 已完成（历史） | 历史已完成；env 已同步 patch |

## 4. 遗留风险

1. **HMFTOOLS `.conda` rsync 未完成前**，66 上 PURPLE 仍会失败；规避：等 `/mnt/neoag_100T/.../tools/HMFTOOLS/.conda/bin/amber` 可执行后再跑 `PURPLE_STEP=pileup`。
2. **假 .gz**：bin 输出可能为 ASCII；已用 `is_usable_seqz`/`cat_seqz` 兼容；最终 merge 产物强制真 gzip。
3. **mhcgnomes patch** 在 env 重装后会丢失；应写入 install skill 的 hardening（后续补）。
4. **sunbinbin 病例本地脚本**未强制改写调用入口；新病人经 `bootstrap` + `run_cnv_all` 的 `shared_tool` 走通用路径。

## 5. 交付引用

- Skill commit：见 git push 后 `origin/main`
- NAS：`shared_scripts/sequenza/run_sequenza_steps.sh` md5 `3e57f590…`
- 病例续跑日志：
  - jinganxin：`…/jinganxin/sequenza/run.resume_gold_20260825_112645.log`
  - yumin：`…/yumin-tumor-rna/dna/sequenza/run.resume_gold_20260825_112649.log`


## 更新 2026-08-25 11:35
撤销 runtime `shared_tool`；模板权威路径改为 neoag-100T `.../shared_scripts/`，病例执行本地副本。
