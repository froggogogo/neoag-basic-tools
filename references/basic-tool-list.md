# basic-tool-list

From `基础版模块、工具和机器.xlsx` plus production closure deps.

## Excel basic tools

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
