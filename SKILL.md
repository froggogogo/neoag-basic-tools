---
name: neoag-basic-tools-install
description: >-
  Portable A1 single-host installer for the basic neoantigen tool chain.
  Creates a centralized dependency tree on zzbnew, discovers or installs
  Conda without hardcoding machine paths, syncs refs/licenses/tools (default
  copy into deps), ensures SpliceMutr genome R packages, and verifies
  readability plus env smoke tests. Use when installing neoantigen basic
  tools, setting up neoag_basic_deps, or preparing any intranet server that
  mounts zzbnew (and zjl for the initial asset copy) to run the basic pipeline.
---

# NeoAg Basic Tools Install

## Goal

On any intranet Linux host that mounts **zzbnew**（写入 deps）and **zjl-bgi-zzb**
（首次灌库读取 asset-source）, run **one command** so the machine gets a complete
**basic** neoantigen tool stack. After install, runtime should depend only on
`$DEPS_DIR` on zzbnew — not on zjl remaining readable.

## One-shot (recommended)

```bash
cd ~/.cursor/skills/neoag-basic-tools-install   # or the skill copy on the server
bash scripts/install.sh --mode install --one-shot --yes
```

`--one-shot` enables:

- `--sync-mode copy`（默认已是 copy）：把 refs/licenses/tools **复制进** zzbnew deps
- `--with-envs` + `--with-tool-scripts`
- `--prefer-deps-conda`：Conda/envs 优先落在 `$DEPS_DIR/software/miniforge3`
- 安装后自动 `--mode verify`（含可读性、env、`BSgenome.Hsapiens.UCSC.hg38`）

## Symlink risk (why default is copy)

If you use `--sync-mode symlink`, deps 里的 `refs/*` 只是指向 zjl 上 neodata4git
的软链。若安装机或其它运行机 **读不到** 源目录（未挂载、ACL、权限），管道会在
运行期失败，而且 soft-fail 很难提前发现。

Installer mitigations:

| Mode | Behavior |
|------|----------|
| `copy`（默认） | 安装期必须能读 asset-source；复制进 zzbnew 后运行不再依赖 zjl |
| `symlink` | 安装前/后探测源与链接可读；不可读则失败并提示改用 copy |
| `sync --force-resync --sync-mode copy` | 拆除已有软链并物化为真实目录 |

## Non-negotiables

- No password printing; use existing SSH/cross-server access if remote ops needed.
- No hard-coded single-host paths in generated `site.env.sh` — only `--deps-dir`.
- Default Conda for one-shot: `$DEPS_DIR/software/miniforge3`（禁止默认装到 `/`）。
- **EasyFuse requires Ubuntu 22.04.** Elsewhere: sync refs only, skip runtime.
- Writes require `--yes` or confirmation.
- Failures print `reason=` + fix hint.

## Default deps root

`/mnt/zzbnew/peixunban/gl/neoag_basic_deps`

## Agent workflow

1. Confirm host sees `/mnt/zzbnew` and (for first sync) `/mnt/zjl-bgi-zzb` / `--asset-source`.
2. `bash scripts/install.sh --mode plan` — show plan; check asset-source **readable**.
3. On approval: `bash scripts/install.sh --mode install --one-shot --yes`
4. Summarize `manifests/verify_report.tsv`（REQUIRED failures, external symlinks, R pkgs）.
5. Tell user: `source $DEPS_DIR/configs/site.env.sh`

If an old install still has external symlinks:

```bash
bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync
bash scripts/install.sh --mode verify
```

## References

- [README.md](README.md)
- [references/deps-layout.md](references/deps-layout.md)
- [references/sync-policy.md](references/sync-policy.md)
- [references/basic-tool-list.md](references/basic-tool-list.md)
