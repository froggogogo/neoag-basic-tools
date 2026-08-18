# 用 Agent 一键运行

## 前置

- 目标机已挂载 `/mnt/neoag_100T`，deps 已安装（见 install skill）
- 病例目录已准备 wrapper（推荐从 sunbinbin 复制 `scripts/`、`short-rna/`）
- 知道 BAM / VCF / FASTQ 路径与完整 neo 仓库路径

## 复制给 Agent 的 Prompt

```text
请按 neoag-basic-tools-run skill 在本机一键运行新抗原基础工具 + 生产接口。

要求：
1. source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
2. cd .../neoag-skills/neoag-basic-tools-run
3. bash scripts/probe_host.sh — 汇报 nproc、mem_gb、mode（serial|dual|full）
4. bash scripts/run.sh --mode plan --yes \
     --case-root <CASE_ROOT> \
     --sample-id <SAMPLE_ID> \
     --neo-root <FULL_NEO_ROOT> \
     --tumor-bam ... --normal-bam ... --somatic-vcf ... \
     --rna-r1 ... --rna-r2 ...
5. 若 plan 合理，执行：
   bash scripts/run.sh --yes （同上参数）
6. 汇报：
   - 主日志路径
   - production outdir 与 evidence_report*.html
   - 失败 stage 与 CONTINUE_ON_ERROR 行为

约束：
- 不要打印密码
- TMP 必须在 CASE_ROOT/tmp
- EasyFuse 仅 Ubuntu 22.04
- 生产必须用完整 neo（--neo-root），不是 deps/src/neo
- 生产须启用 PRIME + BigMHC-IM + DeepImmuno + IEDB；MixMHCpred 作为 PRIME 依赖
- 生产必须跑 NetMHCstabpan（DTU 本地：`$DEPS_DIR/licenses/predictors/netMHCstabpan`）。缺 `Linux_x86_64/bin` + `data/` 则失败，禁止 `--skip-netmhcstabpan`
- BigMHC 必须有 src/predict.py，不要用只有 models/ 的不完整目录
```

## Agent 核对清单

1. `bash scripts/probe_host.sh --json`
2. case 下是否存在 `run_cnv_hla_parallel` 或 `run_hla_all` + `run_cnv_all`
3. `short-rna/scripts/run_star_*` / `run_arriba_*` / `run_star_fusion_*` / `run_easyfuse_*` 等 + `inputs.env.sh`（FusionCatcher 不单独跑）
4. `--neo-root/scripts/generate_production_from_results_manifest.py` 存在
