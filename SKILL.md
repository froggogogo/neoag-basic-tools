---
name: neoag-basic-tools-install
description: >-
  Portable A1 single-host installer for the basic neoantigen tool chain.
  Creates a centralized dependency tree on neoag_100T (default under
  majiaxin/neoag-basic-tools-install-deps), discovers or installs Conda
  without hardcoding machine paths, syncs refs/licenses/tools (default copy
  into deps), ensures SpliceMutr genome R packages, Sequenza r-data.table +
  fread fit patch, MHCflurry path layout, and VEP Perl isolation; verifies
  readability plus env smoke tests. Use when installing neoantigen basic
  tools or setting up neoag-basic-tools-install-deps on any intranet host
  that mounts neoag_100T (and zjl when first copying assets).
---

# NeoAg Basic Tools Install

## Goal

On any intranet Linux host that mounts **neoag_100T**（写入 deps）and **zjl-bgi-zzb**
（首次灌库读取 asset-source）, run **one command** so the machine gets a complete
**basic** neoantigen tool stack. After install, runtime should depend only on
`$DEPS_DIR` on neoag_100T — not on zjl remaining readable.

## One-shot (recommended)

```bash
cd /path/to/neoag-basic-tools-install
bash scripts/install.sh --mode install --one-shot --yes
```

`--one-shot` enables:

- `--sync-mode copy`：把 refs/licenses/tools **复制进** deps
- `--with-envs` + `--with-tool-scripts`
- `--prefer-deps-conda`：Conda/envs 优先落在 `$DEPS_DIR/software/miniforge3`
- 安装后自动 `--mode verify`
- **运行期加固**：`r-data.table`、MHCflurry 布局、Sequenza fit fread 补丁
- **环境创建优先 mamba**；无 mamba 时回退 conda

## Runtime hardening

See [references/runtime-hardening.md](references/runtime-hardening.md). Summary:

| Issue | Installer action |
|-------|------------------|
| Sequenza fit vroom / fake `.gz` | `ensure_sequenza_datatable` + `scripts/patches/run_sequenza_fit.fread.R` |
| MHCflurry missing / wrong path | `ensure_mhcflurry_layout`；`site.env` 设 `MHCFLURRY_DATA_DIR` |
| VEP Perl 串台（miniconda） | `source site.env.sh` 后调用 `neoag_use_vep_perl` |
| 外部 fit 脚本尚未打补丁 | `bash scripts/apply_sequenza_fit_fread_patch.sh --fit-r /path/to/run_sequenza_fit.R` |

## Symlink risk (why default is copy)

`--sync-mode symlink` 时 `refs/*` 指向 asset-source。若运行机读不到源目录，管道会在运行期失败。

| Mode | Behavior |
|------|----------|
| `copy`（默认） | 安装期必须能读 asset-source；复制后运行不再依赖 zjl |
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

## Skill vs neo

本 skill **独立于** neo 仓库；安装机不必再 clone neo。

- 建 env / 跑 `install_*.sh` 使用 **`$DEPS_DIR/src/neo` 安装切片**（`conda/env.neoag-*.yml`、`scripts/install_*.sh`、`scripts/run_sequenza_fit.R`）。
- 若 deps 已含该切片：直接 `install.sh --one-shot`。
- 若切片缺失：用 `--neo-src /path/to/neo` 灌入一次，或使用已预置切片的共享 deps。

## Install workflow

1. Confirm `/mnt/neoag_100T`；首次灌库还需可读的 `--asset-source`。
2. `bash scripts/install.sh --mode plan`
3. `bash scripts/install.sh --mode install --one-shot --yes`
4. Check `manifests/verify_report.tsv`
5. `source $DEPS_DIR/configs/site.env.sh`

If an old install still has external symlinks:

```bash
bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync
bash scripts/install.sh --mode verify
```

## References

- [README.md](README.md)
- [docs/USAGE_AGENT.md](docs/USAGE_AGENT.md) — Agent 安装 Prompt
- [docs/USAGE_MANUAL.md](docs/USAGE_MANUAL.md) — 人工一键安装
- [references/deps-layout.md](references/deps-layout.md)
- [references/sync-policy.md](references/sync-policy.md)
- [references/basic-tool-list.md](references/basic-tool-list.md)
- [references/runtime-hardening.md](references/runtime-hardening.md)
