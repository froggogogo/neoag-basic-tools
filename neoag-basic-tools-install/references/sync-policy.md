# sync-policy

## Why default is `copy`

`refs/` under `$DEPS_DIR` must be usable on any host that only mounts **neoag_100T**
(default deps root).

`symlink` points into `--asset-source` (usually on **zjl-bgi-zzb**). That fails when:

- the run host does not mount zjl
- the path exists but ACL/permissions deny the pipeline user
- the mount is stale / read-only for that UID

Therefore:

1. **Install / one-shot default**: `--sync-mode copy`
2. **symlink allowed** only for quick lab experiments when both disks are always mounted and readable
3. **Installer checks**: source and resulting paths must pass a read probe (`list` + `head -c 1` on a sample file); otherwise abort with `ASSET_UNREADABLE` / `SYMLINK_UNREADABLE`

## Migrating an old symlink install

```bash
bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync
bash scripts/install.sh --mode verify
```

This removes external symlinks under `refs/` / `licenses/` / `tools/neodata_tools` and rsyncs real trees into `$DEPS_DIR`.

## Install-time vs run-time mounts

| Phase | neoag_100T (deps) | zjl (asset-source) |
|-------|-------------------|--------------------|
| Shared deps already filled | required (write for envs/site.env) | **not required** |
| Missing refs / `--force-resync` | required (write) | required (**readable**) |
| Later run / verify | required | not required |
| symlink mode | required | **still required readable** |

## `src/neo` install slice

`$DEPS_DIR/src/neo` is **not** a full neo git tree. It only needs:

- `conda/env.neoag-*.yml` used by the installer
- `scripts/install_*.sh` invoked by `--with-tool-scripts`
- `scripts/run_sequenza_fit.R` for runtime hardening

Install hosts mount a deps tree that already contains this slice, or pass
`--neo-src` once to seed it. They do not need to clone the neo repository.
