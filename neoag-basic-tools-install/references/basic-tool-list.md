# basic-tool-list

Basic neoantigen tool profile for this installer.

## Basic tools

| Module | Tool |
|--------|------|
| HLA分型 | OptiType, SpecHLA, HLA-LA |
| 肿瘤纯度/CNV | FACETS, Sequenza, PURPLE |
| HLA-I LOH | LOHHLA, SpecHLA |
| RNA表达 | Salmon |
| Fusion | EasyFuse (**Ubuntu 22.04 only**), STAR-Fusion |

### EasyFuse

- Hard OS requirement: **Ubuntu 22.04**
- On other hosts: do not treat EasyFuse runtime as REQUIRED; use STAR-Fusion (and optional Arriba) for fusion evidence
- Shared refs under `refs/easyfuse` may still be synced for use on 22.04 machines

| Splice | SNAF, SpliceMutr (**requires `BSgenome.Hsapiens.UCSC.hg38` in neoag-splicemutr**) |
| 最终分析 | 生产接口（neoag production） |

## Closure dependencies (required for stable run)

STAR/samtools, VEP(+cache), pVACtools / MHCflurry, GATK (as needed),
reference FASTA/GTF/CTAT, and licensed predictors when available.

### Sequenza (pileup + fit)

Gold: sunbinbin 2026-08-17 chrom-split fread (`references/runtime-hardening.md`).

- Env `neoag-sequenza`: **sequenza-utils**, R `sequenza`, **`r-data.table`**
- Env `neoag-samtools19`: **samtools=1.9** for bam2seqz mpileup (not 1.23)
- `$DEPS_DIR/tools/sequenza/bam2seqz_nulsafe.py` (NUL in pileup)
- `$DEPS_DIR/tools/sequenza/run_sequenza_steps.sh`
- Fit script must contain **`split_seqz_by_chrom`** (not whole-file vroom/`skip=`)
- GC wiggle under `refs/sequenza/reference/`; FASTA contig style **chr\***

### MHCflurry (ranking)

- Models under `~/.local/share/mhcflurry/2.0.0/...` (shim `2.0.0 → 4/2.0.0` if needed)
- Prefer annotated CSQ VCF for SNV to avoid re-running VEP on polluted Perl hosts

### VEP

- Isolate `PERL5LIB` to `neoag-vep` only (`neoag_use_vep_perl` in `site.env.sh`)

### Production predictors (licensed + profile)

Required files under `$DEPS_DIR/licenses/predictors` (verify as OPTIONAL_LICENSED):

| Tool | Sentinel |
|------|----------|
| BigMHC-IM | `bigmhc/src/predict.py` |
| DeepImmuno | `DeepImmuno/deepimmuno-cnn.py` |
| MixMHCpred | `mixMHCpred_install/MixMHCpred`（PRIME `-mix` 依赖） |
| PRIME | `prime/PRIME` |
| NetChop | `netchop/netchop-3.1/Linux_x86_64/bin/netChop` |
| NetMHCstabpan | `Linux_x86_64/bin/netMHCstabpan` + `data/`（DTU；不要用 IEDB shim） |
| IEDB | 无二进制；run skill 把 sarcoma profile `sources` 列入 `iedb` |

`site.env.sh` 按 sentinel 挑选目录，不要指向只有 `models/` 的不完整 BigMHC。
运行期 profile 与 overlay 见 run skill `references/production-predictors.md`。

