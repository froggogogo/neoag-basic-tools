---
name: neoag-basic-tools-install
description: >-
  Portable A1 single-host installer for the basic neoantigen tool chain.
  Creates a centralized dependency tree on neoag_100T (default under
  majiaxin/neoag-basic-tools-install-deps), discovers or installs Conda
  without hardcoding machine paths, syncs refs/licenses/tools (default copy
  into deps), ensures SpliceMutr genome R packages, Sequenza chrom-split
  fread fit plus bam2seqz NUL wrapper and samtools 1.9, MHCflurry path layout,
  and VEP Perl isolation; verifies readability plus env smoke tests. Use when
  installing neoantigen basic tools or setting up neoag-basic-tools-install-deps
  on any intranet host that mounts neoag_100T. Does not run patient cases
  (that is neoag-basic-tools-run). zjl is only needed if shared deps are
  still missing.
---

# NeoAg Basic Tools Install

## Goal

On any intranet Linux host that mounts **neoag_100T**, run **one command** so the
machine gets a complete **basic** neoantigen tool stack. Shared refs live in
`$DEPS_DIR`. **zjl is not required** when deps already contain the assets
(A-class copy onto neoag_100T). zjl / `--asset-source` is only for filling
missing items.

## One-shot (recommended)

```bash
cd /path/to/neoag-skills/neoag-basic-tools-install
bash scripts/install.sh --mode install --one-shot --yes
```

`--one-shot` enables:

- `--sync-mode copy`：把 refs/licenses/tools **复制进** deps
- `--with-envs` + `--with-tool-scripts`
- `--prefer-deps-conda`：Conda/envs 优先落在 `$DEPS_DIR/software/miniforge3`
- 安装后自动 `--mode verify`
- **运行期加固**：`r-data.table`、Sequenza chrom-split fit、`bam2seqz_nulsafe`、samtools 1.9、MHCflurry 布局
- **环境创建优先 mamba**；无 mamba 时回退 conda
- **本机 conda**：不往 OSS/FUSE 的 neoag_100T 装 Miniforge；`site.env.sh` source 时发现 134/66/169 上已有的 miniforge

## Runtime hardening

See [references/runtime-hardening.md](references/runtime-hardening.md). Summary:

| Issue | Installer action |
|-------|------------------|
| Sequenza fit vroom / fake `.gz` / mmap crash | chrom-split fread：`scripts/patches/run_sequenza_fit.fread.R` + `r-data.table` |
| Sequenza bam2seqz NUL (`samtools` 1.23) | `tools/sequenza/bam2seqz_nulsafe.py` + env `neoag-samtools19` |
| MHCflurry missing / wrong path | `ensure_mhcflurry_layout`；`site.env` 设 `MHCFLURRY_DATA_DIR` |
| BigMHC 缺 `src/predict.py` | `ensure_bigmhc_predict_py`；`site.env` 按 sentinel 选完整树 |
| NetMHCstabpan 只有 IEDB shim | `ensure_netmhcstabpan_dtu` 检查 `$DEPS_DIR` 内是否已有 DTU 树（不从其他网盘拉取） |
| VEP Perl 串台（miniconda） | `source site.env.sh` 后调用 `neoag_use_vep_perl` |
| 外部 fit 脚本尚未打补丁 | `bash scripts/apply_sequenza_fit_fread_patch.sh --fit-r /path/to/run_sequenza_fit.R` |

## Symlink risk (why default is copy)

`--sync-mode symlink` 时 `refs/*` 指向 asset-source。若运行机读不到源目录，管道会在运行期失败。

| Mode | Behavior |
|------|----------|
| `copy`（默认） | deps 已有可读目录则跳过，不碰 zjl；仅缺项才从 asset-source 复制 |
| `symlink` | 探测源与链接可读；不可读则失败并提示改用 copy |
| `sync --force-resync --sync-mode copy` | 拆除软链并物化为真实目录 |

## Non-negotiables

- Do not print passwords or secrets.
- Generated `site.env.sh` only uses `--deps-dir` paths.
- Default Conda for one-shot: `$DEPS_DIR/software/miniforge3`（禁止默认装到 `/`）。
- **EasyFuse requires Ubuntu 22.04.** Elsewhere: sync refs only, skip EasyFuse runtime.
- Writes require `--yes` or confirmation.
- Failures print `reason=` + fix hint.

## Default deps root

`/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps`

## Shared refs (RSEM / EasyFuse conda / SpliceMutr R)

Canonical under `$DEPS_DIR/shared_refs/` (migrated off zzbnew):

| Path | Env |
|------|-----|
| `shared_refs/rsem_gencode_v49/gencode_v49` | `RSEM_REFERENCE` |
| `shared_refs/easyfuse_nextflow_conda` | `EASYFUSE_NEXTFLOW_CONDA` |
| `shared_refs/R_library_splicemutr` | `SPLICEMUTR_R_LIBS` → prepended to `R_LIBS_SITE` |

`site.env.sh` / `site_runtime.sh` export these when the dirs exist. Templates live in `$DEPS_DIR/shared_scripts/splicemutr/`.

## Shared conda (host prefix, not OSS)

`--one-shot` **不会**把 Miniforge 装到 neoag_100T（OSS/FUSE 上 conda 前缀会坏）。本机发现顺序：

| 主机 | Conda |
|------|--------|
| 134 | `/home/na/miniforge3` |
| 66 | `/root/neo/envs/miniforge3`（`env_tool` → 同一棵树） |
| 169 | `/root/neo/env_tool/miniforge3` |

补齐本机缺失 env（samtools 1.9、BSgenome、data.table、conda-pack 金标准 env）：

```bash
bash scripts/ensure_host_runtime.sh
bash scripts/host_verify.sh
```

其它机器挂上同一块 `neoag_100T` 后：

```bash
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
```

`site.env.sh` 会在 **source 时**发现本机 conda / 工具树，不再写死安装机路径。

`--prefer-deps-conda` 仅当 deps 在本地盘（非 FUSE）时才把 Miniforge 装进 `$DEPS_DIR/software/miniforge3`。

## Skill vs neo

本 skill **独立于** neo 仓库；安装机不必再 clone neo。

- 建 env / 跑 `install_*.sh` 使用 **`$DEPS_DIR/src/neo` 安装切片**（`conda/env.neoag-*.yml`、`scripts/install_*.sh`、`scripts/run_sequenza_fit.R`）。
- 若 deps 已含该切片：直接 `install.sh --one-shot`。
- 若切片缺失：用 `--neo-src /path/to/neo` 灌入一次，或使用已预置切片的共享 deps。

## Install workflow

1. Confirm `/mnt/neoag_100T` and `$DEPS_DIR`. zjl only if some refs are still missing.
2. `bash scripts/install.sh --mode plan`
3. `bash scripts/install.sh --mode install --one-shot --yes`
4. Check `manifests/verify_report.tsv`
5. `source $DEPS_DIR/configs/site.env.sh`

If an old install still has external symlinks:

```bash
bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync
bash scripts/install.sh --mode verify
```

安装完成后用**独立**运行 Skill（兄弟目录，不要从本目录嵌套调用）：
[../neoag-basic-tools-run/SKILL.md](../neoag-basic-tools-run/SKILL.md)

- [README.md](README.md)
- [docs/USAGE_AGENT.md](docs/USAGE_AGENT.md) — Agent 安装 Prompt
- [docs/USAGE_MANUAL.md](docs/USAGE_MANUAL.md) — 人工一键安装
- [references/deps-layout.md](references/deps-layout.md)
- [references/sync-policy.md](references/sync-policy.md)
- [references/basic-tool-list.md](references/basic-tool-list.md)
- [references/runtime-hardening.md](references/runtime-hardening.md)
