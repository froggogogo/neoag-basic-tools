# deps-layout

Canonical tree under `--deps-dir` (default
`/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps`):

```text
refs/hg38|vep|hla|ctat|rna|easyfuse|facets|hmf|lohhla|ascat|sequenza|snaf|normal|sample_identity
licenses/predictors/          # netMHCpan, prime, mixMHCpred, bigmhc, DeepImmuno
                              # BigMHC 必须含 src/predict.py（仅 models/ 不够）
packages/{installers,conda_pkgs,pip_cache}
tools/{neodata_tools,EasyFuse,STAR-Fusion,sequenza,…}
                              # sequenza/: bam2seqz_nulsafe.py, run_sequenza_steps.sh, chrom-split fit R
software/miniforge3           # shared conda (--one-shot). First host downloads here;
                              # later hosts reuse envs/; do not install to /home
configs/site.env.sh           # source this to activate PATH + refs (not a reinstall)
src/neo                       # install-skill slice only (yml + install_*.sh + fit R)
manifests/{sync_assets,conda_envs,verify_report}.tsv
logs/
work/nextflow_cache/
```

`configs/site.env.sh` must reference **only** paths under `DEPS_DIR`.

Prefer **real directories** under `refs/` (sync-mode copy). External symlinks are
allowed only for experiments; verify will warn with `EXTERNAL_SYMLINK`.
