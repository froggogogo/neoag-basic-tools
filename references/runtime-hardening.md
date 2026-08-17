# Runtime hardening (lessons from production runs)

Operational fixes discovered while running DSRCT / neoag Wave A jobs.
The installer applies what it can automatically; agents must still apply
pipeline-side patches when the neo tree is not owned by this skill.

## 1. Sequenza fit — fake `.gz` + vroom / fread

### Symptoms

- `Error: The size of the connection buffer … was not large enough to fit a complete line`
- Raising `VROOM_CONNECTION_SIZE` (even to 256MB) still fails
- `gzip -t sample.small.seqz.gz` → **not in gzip format**
- `file sample.small.seqz.gz` → **ASCII text**

### Root cause

`sequenza-utils seqz_binning` sometimes writes **plain TSV** while keeping the
`.seqz.gz` name. `sequenza::gc.sample.stats` / `read.seqz` use `gzfile` +
`readr::read_tsv` (vroom), which treat the path as gzip and blow up.

Line lengths are usually normal; **do not** start by hunting “multi‑MB lines”
with `zcat` (zcat itself fails on fake gz).

### Required stack

1. Install **`r-data.table`** into `neoag-sequenza` (installer does this).
2. Patch fit to use **`data.table::fread`** via `assignInNamespace` on
   `gc.sample.stats` and `read.seqz` (template:
   `scripts/patches/run_sequenza_fit.fread.R`).
3. Detect non-gzip magic (`1f 8b`); hardlink/rename to `.seqz` without `.gz`
   before reading (fread also assumes `.gz` ⇒ gzip).
4. Convert chunk results to a **list-matrix** before `unfold_gc` (it indexes
   `x[, "gc_nor"]` etc.).
5. **Do not** set `environment(fn) <- asNamespace("sequenza")` and then
   `get("unfold_gc", envir = ns)` — free-var `ns` is missing inside the
   package namespace. Prefer **closures** capturing `unfold_gc_fn` +
   `assignInNamespace`.

### Apply patch

```bash
# After source site.env.sh
bash ~/.cursor/skills/neoag-basic-tools-install/scripts/apply_sequenza_fit_fread_patch.sh \
  --fit-r /path/to/neo/scripts/run_sequenza_fit.R
```

## 2. MHCflurry models path / user HOME

### Symptoms

```text
Missing MHCflurry downloadable file:
  /root/.local/share/mhcflurry/.../models_class1_presentation/models
# or
  ~/.local/share/mhcflurry/2.0.0/models_class1_presentation/models
```

while models actually live under:

```text
~/.local/share/mhcflurry/4/2.0.0/models_class1_presentation/models
```

### Fixes

1. Prefer running production as the user who owns the downloads (`na`), or set
   `HOME` / `MHCFLURRY_DATA_DIR` before `run-full`.
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

4. Note: some runners spawn `mhcflurry-predict` with a **minimal env** (only
   `TF_USE_LEGACY_KERAS`). Symlink under the process user’s
   `~/.local/share/mhcflurry/2.0.0` is more reliable than env alone.

## 3. VEP Perl environment isolation

### Symptoms (esp. on hosts with `/root/miniconda3`)

```text
Compilation failed … Bio/EnsEMBL/VEP/…
…/root/miniconda3/lib/perl5/core_perl/base.pm
```

### Fixes

1. Before calling `vep`, set `PERL5LIB` **only** from `neoag-vep` (see
   `site.env.sh` → `neoag_use_vep_perl`). Never prepend system/miniconda Perl.
2. Prefer feeding production an **already CSQ-annotated** VCF
   (`##INFO=<ID=CSQ`). Upstream skips auto-VEP when CSQ is present — reuse
   patient DNA VEP outputs across RNA aliases (e.g. aipang ← yumin DNA).

## 4. NetMHCpan on mixed hosts

Bundled NetMHCpan ELF may need a conda sysroot / docker image
(`neoag-netmhcpan:…`). Prefer a local wrapper that `docker run`s with
`/mnt` mounts (as used successfully on 134). Do not assume bare binary works
on every host.

## 5. Ops hygiene

- Do not leave unbounded `find /mnt/zzbnew …` / `find /mnt/zjl-bgi-zzb …`
  inventory jobs overnight; they pin load via NFS D-state.
- Cap depth (`-maxdepth`) and always time-box or `timeout`.
