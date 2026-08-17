# Runtime hardening

Known runtime pitfalls the installer mitigates (or documents) for the basic
tool stack.

## 1. Sequenza fit — fake `.gz` + vroom / fread

### Symptoms

- `Error: The size of the connection buffer … was not large enough to fit a complete line`
- Raising `VROOM_CONNECTION_SIZE` still fails
- `gzip -t sample.small.seqz.gz` → **not in gzip format**
- `file sample.small.seqz.gz` → **ASCII text**

### Root cause

`sequenza-utils seqz_binning` sometimes writes **plain TSV** while keeping the
`.seqz.gz` name. `sequenza::gc.sample.stats` / `read.seqz` use `gzfile` +
`readr::read_tsv` (vroom), which treat the path as gzip and fail.

### Required stack

1. Install **`r-data.table`** into `neoag-sequenza` (installer does this).
2. Patch fit to use **`data.table::fread`** via `assignInNamespace` on
   `gc.sample.stats` and `read.seqz` (template:
   `scripts/patches/run_sequenza_fit.fread.R`).
3. Detect non-gzip magic (`1f 8b`); hardlink/rename to `.seqz` without `.gz`
   before reading.
4. Convert chunk results to a **list-matrix** before `unfold_gc`.
5. Prefer **closures** capturing helpers + `assignInNamespace`; do not assign
   `environment(fn) <- asNamespace("sequenza")` and then look up free vars
   from a missing `ns`.

### Apply patch

```bash
# After source site.env.sh
bash scripts/apply_sequenza_fit_fread_patch.sh \
  --fit-r /path/to/run_sequenza_fit.R
```

## 2. MHCflurry models path / user HOME

### Symptoms

```text
Missing MHCflurry downloadable file:
  ~/.local/share/mhcflurry/.../models_class1_presentation/models
```

while models actually live under:

```text
~/.local/share/mhcflurry/4/2.0.0/models_class1_presentation/models
```

### Fixes

1. Set `HOME` / `MHCFLURRY_DATA_DIR` for the user that owns the downloads.
2. Layout shim (installer `ensure_mhcflurry_layout`):

```bash
# If 4/2.0.0 exists but 2.0.0 does not:
ln -sfn "$MF/4/2.0.0" "$MF/2.0.0"
```

3. Fetch if missing:

```bash
source "$DEPS_DIR/configs/site.env.sh"
mhcflurry-downloads fetch models_class1_presentation
```

4. Some runners spawn `mhcflurry-predict` with a minimal env; a symlink under
   that process user’s `~/.local/share/mhcflurry/2.0.0` is more reliable than
   env alone.

## 3. VEP Perl environment isolation

### Symptoms (hosts with a system/miniconda Perl)

```text
Compilation failed … Bio/EnsEMBL/VEP/…
…/miniconda3/lib/perl5/core_perl/base.pm
```

### Fixes

1. Before calling `vep`, set `PERL5LIB` **only** from `neoag-vep` (see
   `site.env.sh` → `neoag_use_vep_perl`). Never prepend system/miniconda Perl.
2. Prefer an **already CSQ-annotated** VCF (`##INFO=<ID=CSQ`) when upstream
   skips auto-VEP.

## 4. NetMHCpan on mixed hosts

Bundled NetMHCpan ELF may need a conda sysroot or docker image. Prefer a
wrapper that mounts shared NAS paths consistently. Do not assume the bare
binary works on every host.
