# Runtime hardening

Known runtime pitfalls the installer mitigates (or documents) for the basic
tool stack.

## 1. Sequenza — fake `.gz` + chrom-split fread + samtools NUL

Gold path: **sunbinbin 2026-08-17** (`cellularity 0.81 / ploidy 2`, `.fit.done`).

### Symptoms

- `Error: The size of the connection buffer … was not large enough to fit a complete line`
- Raising `VROOM_CONNECTION_SIZE` still fails
- `gzip -t sample.small.seqz.gz` → **not in gzip format**
- `file sample.small.seqz.gz` → **ASCII text**
- `ValueError: embedded null character` in `sequenza.c_pileup` / `do_seqz`
- `fread` mmap / `skip=` segfault on a ~25G plain `small.seqz`

### Root cause

1. `sequenza-utils seqz_binning` sometimes writes **plain TSV** while keeping the
   `.seqz.gz` name. `sequenza::gc.sample.stats` / `read.seqz` use `gzfile` +
   `readr::read_tsv` (vroom).
2. Whole-file `fread(skip=)` on that TSV can mmap-crash. **Split by chromosome**
   first, then `fread` each chrom with `mmap=FALSE`, `nThread=1`.
3. samtools **1.23** mpileup can emit NULs; sequenza C parser dies. Use
   **samtools 1.9** for `-S` plus `bam2seqz_nulsafe.py`.

### Required stack (installer)

1. Env `neoag-sequenza`: `sequenza` + `sequenza-utils` + **`r-data.table`**.
2. Env `neoag-samtools19`: **samtools=1.9** (mpileup only; tabix stays in sequenza env).
3. Copy into `$DEPS_DIR/tools/sequenza/`:
   - `bam2seqz_nulsafe.py`
   - `run_sequenza_steps.sh`
   - `run_sequenza_fit.R` (chrom-split fread; same as `scripts/patches/run_sequenza_fit.fread.R`)
4. Patch `$DEPS_DIR/src/neo/scripts/run_sequenza_fit.R` to the chrom-split script.
5. GC wiggle: `refs/sequenza/reference/*gc50.wig.gz`
6. FASTA must be **GATK chr\*** contig style (not Ensembl `1,2,10`).

### Run

```bash
source "$DEPS_DIR/configs/site.env.sh"
export SAMPLE_ID TUMOR_BAM NORMAL_BAM OUTDIR="$CASE_ROOT/sequenza"
bash "$DEPS_DIR/tools/sequenza/run_sequenza_steps.sh"
```

Or the independent run skill CNV stage (`../neoag-basic-tools-run/scripts/stages/sequenza.sh`).

### Apply fit patch to an external neo tree

```bash
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

## 5. Production predictors — incomplete BigMHC / disabled immuno sources

### Symptoms (sunbinbin 20260814 provenance)

- `bigmhc_im` status `missing` while `licenses/predictors/bigmhc` looks populated
- `deepimmuno` / `iedb` status `not_used`

### Root cause

1. `BIGMHC_DIR` pointed at a tree with **only** `models/` (no `src/predict.py`).
2. Sarcoma profile `sources = ["prime", "bigmhc_im"]` omitted DeepImmuno and IEDB.

### Installer

- Verify sentinels: `bigmhc/src/predict.py`, `DeepImmuno/deepimmuno-cnn.py`, `MixMHCpred`, `PRIME`,
  NetMHCstabpan `Linux_x86_64/bin/netMHCstabpan`（不要把 IEDB Python shim 当 DTU 安装）
- `site.env` `neoag_export_production_predictors` picks the first tree that has the sentinel
- `ensure_bigmhc_predict_py` copies `src/` from `NEOAG_PRED_FALLBACK` if deps is models-only

Profile overlay belongs in the **run** skill (`ensure_neo_production.sh`).
