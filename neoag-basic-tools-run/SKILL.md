---
name: neoag-basic-tools-run
description: >-
  One-shot neoantigen basic-tools runner with host probe and adaptive
  parallelism (serial | dual | full). Drives HLA, CNV (including the
  sunbinbin Sequenza gold path: NUL-safe bam2seqz + chrom-split fread fit),
  LOHHLA, short-bulk RNA, SNAF, SpliceMutr, VEP, then neoag production_runner
  for evidence reports. Does not install tools — run neoag-basic-tools-install
  first, then source site.env.sh. Use when running a prepared case on
  intranet hosts 66/134/169.
---

# NeoAg Basic Tools Run

## Goal

After **neoag-basic-tools-install**, run the **basic tool chain** for one
sample, then **production** (evidence + reports). Schedule follows **sunbinbin**
(most complete reference case): parallel when CPU/RAM allow, serial otherwise.

## Prerequisites

1. Shared deps installed and readable:
   `/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps`
2. `source $DEPS_DIR/configs/site.env.sh`
3. **Case directory** with per-sample wrappers (copy/adapt from sunbinbin), e.g.:
   - `scripts/run_cnv_hla_parallel_*.sh` or separate `run_hla_all` / `run_cnv_all`
   - `short-rna/scripts/run_*` per-tool wrappers + `inputs.env.sh`（须有 STAR / Arriba / STAR-Fusion / EasyFuse；FusionCatcher 不单独跑）
   - optional: `run_lohhla`, `run_snaf`, `run_splicemutr_patient`, `run_vep_somatic`
4. **Production** needs a **full neo repo** (`--neo-root`), not install slice
   `$DEPS_DIR/src/neo`.

## One-shot run

```bash
cd /path/to/neoag-skills/neoag-basic-tools-run
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh

bash scripts/probe_host.sh                    # 探查核数/内存 → serial|dual|full
bash scripts/run.sh --mode plan --yes \
  --case-root /mnt/zzbnew/.../sunbinbin \
  --sample-id sunbinbin \
  --neo-root /home/na/project/neoantigen/neoag_event_pipeline_na0707_sync_20260811 \
  --tumor-bam ... --normal-bam ... --somatic-vcf ... \
  --rna-r1 ... --rna-r2 ...

bash scripts/run.sh --yes \
  --case-root /mnt/zzbnew/.../sunbinbin \
  --sample-id sunbinbin \
  --neo-root /path/to/full/neo \
  --tumor-bam ... --normal-bam ... --somatic-vcf ...
```

## Host probe → schedule

| mode | CPU | RAM | DAG |
|------|-----|-----|-----|
| **serial** | &lt;12 | &lt;48G | HLA → CNV → RNA → … |
| **dual** | ≥12 | ≥48G | (HLA queue ∥ CNV queue) → RNA → … |
| **full** | ≥20 | ≥96G | (HLA ∥ CNV) ∥ RNA（STAR∥SF → Arriba → EasyFuse）→ … |

Override: `--sched serial|dual|full`. Thresholds: env
`MIN_DUAL_NPROC`, `MIN_DUAL_MEM_GB`, `MIN_FULL_NPROC`, `MIN_FULL_MEM_GB`.

Internal queues stay **serial** (sunbinbin): CNV FACETS→**Sequenza (builtin gold runner)**→PURPLE→ASCAT;
HLA OptiType→SpecHLA→HLA-LA; RNA STAR∥STAR-Fusion then Arriba/RegTools then EasyFuse（FusionCatcher 仅 EasyFuse 内）→ pVACfuse.

## Stages (master DAG)

1. **HLA** + **CNV** (parallel per schedule)
2. **RNA** short-bulk (parallel in `full` mode)
3. **LOHHLA** (needs HLA + purity)
4. **SNAF** → **SpliceMutr** (needs HLA + junctions). SNAF gold path is
   `scripts/tools/snaf/run_snaf_pipeline.sh` (single STAR BAM, **no**
   fake `sample_replicate`, STAR `SJ.out.tab` gate, genomic start≤end).
   SpliceMutr helper `scripts/tools/splicemutr/prepare_splicemutr_candidates.py`
   also forces start≤end.
5. **VEP** (optional if `--somatic-vcf` set)
6. **production** — overlay neo `tools.env.local.sh` + sarcoma immunogenicity
   sources（PRIME / BigMHC-IM / DeepImmuno；IEDB 仅 NetMHCpan 失败时兜底），呈递含
   NetMHCpan / MHCflurry / **NetMHCstabpan（DTU 本地，必跑；缺树则失败）** / NetChop，再
   `generate_production_from_results_manifest.py` +
   `python -m neoag.production_runner --execute`

Skip production: `--skip-production`.

MixMHCpred 不是独立 immunogenicity source，由 PRIME `-mix` 调用；路径必须可执行。
详见 [references/production-predictors.md](references/production-predictors.md)。

## Non-negotiables

- Do not print passwords.
- Large temp under `$CASE_ROOT/tmp` (never root `/tmp` on full disks).
- EasyFuse only on Ubuntu 22.04; probe reports `easyfuse_os`.
- Respect `.done` markers; `--force` to rerun.
- `CONTINUE_ON_ERROR=1` default (like sunbinbin).

## References

- [README.md](README.md)
- [docs/USAGE_AGENT.md](docs/USAGE_AGENT.md)
- [docs/USAGE_MANUAL.md](docs/USAGE_MANUAL.md)
- [references/schedule.md](references/schedule.md)
- [references/sunbinbin-map.md](references/sunbinbin-map.md)
- [references/production-predictors.md](references/production-predictors.md)
- Install skill: [../neoag-basic-tools-install/SKILL.md](../neoag-basic-tools-install/SKILL.md)
