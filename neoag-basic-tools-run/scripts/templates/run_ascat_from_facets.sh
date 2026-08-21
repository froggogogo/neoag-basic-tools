#!/usr/bin/env bash
# ASCAT from FACETS snp-pileup CSV/CSV.GZ.
# ASCAT_STEP=pileup  -> convert pileup to LogR/BAF (no BAM I/O)
# ASCAT_STEP=fit     -> ascat.aspcf + ascat.runAscat
# ASCAT_STEP=all     -> both
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib_portable_env.sh"
ROOT="${NEOAG_ROOT}"

SAMPLE_ID="${SAMPLE_ID:?ERROR: set SAMPLE_ID}"
PILEUP="${PILEUP:?ERROR: set PILEUP=/path/to/facets.pileup.csv[.gz]}"
OUT="${OUTDIR:?ERROR: set OUTDIR}"
LOG="${LOG:-${OUT}/run.log}"
ASCAT_STEP="${ASCAT_STEP:-all}"
FORCE="${FORCE:-0}"
CONDA_BASE="${NEOAG_CONDA_BASE:?ERROR: NEOAG_CONDA_BASE unset}"
ASCAT_ENV="${NEOAG_ASCAT_ENV:-neoag-ascat}"
RSCRIPT="${RSCRIPT:-${CONDA_BASE}/envs/${ASCAT_ENV}/bin/Rscript}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
MIN_NORMAL_DEPTH="${ASCAT_MIN_NORMAL_DEPTH:-20}"
MIN_TUMOR_DEPTH="${ASCAT_MIN_TUMOR_DEPTH:-20}"
MIN_NORMAL_BAF="${ASCAT_MIN_NORMAL_BAF:-0.10}"
MAX_NORMAL_BAF="${ASCAT_MAX_NORMAL_BAF:-0.90}"
MAX_SNPS="${ASCAT_MAX_SNPS:-300000}"
ASCAT_PENALTY="${ASCAT_PENALTY:-25}"
ASCAT_GAMMA="${ASCAT_GAMMA:-0.55}"

DONE_PILEUP="${OUT}/.pileup.done"
DONE_FIT="${OUT}/.fit.done"
TUMOR_LOGR="${OUT}/${SAMPLE_ID}.tumor.LogR.txt"

mkdir -p "${OUT}" "$(dirname "${LOG}")"
exec > >(tee -a "${LOG}") 2>&1

echo "==> ascat_from_facets $(date -Is) step=${ASCAT_STEP}"
echo "    sample=${SAMPLE_ID}"
echo "    pileup=${PILEUP}"
echo "    out=${OUT}"

[[ -s "${PILEUP}" ]] || { echo "ERROR: missing pileup: ${PILEUP}" >&2; exit 1; }
[[ -x "${RSCRIPT}" ]] || { echo "ERROR: missing Rscript: ${RSCRIPT}" >&2; exit 1; }

do_pileup() {
  if [[ -s "${TUMOR_LOGR}" && -f "${DONE_PILEUP}" && "${FORCE}" != "1" ]]; then
    echo "==> ASCAT inputs already present"
    return 0
  fi
  CONVERT_SCRIPT="${OUT}/convert_facets_pileup_to_ascat_inputs.py"
  cat > "${CONVERT_SCRIPT}" <<'PY'
from __future__ import annotations
import csv, gzip, math, os, statistics
from pathlib import Path

pileup = Path(os.environ["PILEUP"])
out = Path(os.environ["OUT"])
sample = os.environ["SAMPLE_ID"]
min_normal_depth = int(float(os.environ.get("MIN_NORMAL_DEPTH", "20")))
min_tumor_depth = int(float(os.environ.get("MIN_TUMOR_DEPTH", "20")))
min_normal_baf = float(os.environ.get("MIN_NORMAL_BAF", "0.10"))
max_normal_baf = float(os.environ.get("MAX_NORMAL_BAF", "0.90"))
max_snps = int(float(os.environ.get("MAX_SNPS", "0")))

out.mkdir(parents=True, exist_ok=True)
rows = []
opener = gzip.open if str(pileup).endswith(".gz") else open
with opener(pileup, "rt", newline="") as fh:  # type: ignore[arg-type]
    reader = csv.DictReader(fh)
    for row in reader:
        chrom = (row.get("Chromosome") or "").removeprefix("chr")
        if chrom not in {str(i) for i in range(1, 23)}:
            continue
        pos = row.get("Position") or ""
        try:
            n_ref = int(row.get("File1R") or 0)
            n_alt = int(row.get("File1A") or 0)
            t_ref = int(row.get("File2R") or 0)
            t_alt = int(row.get("File2A") or 0)
        except ValueError:
            continue
        nd = n_ref + n_alt
        td = t_ref + t_alt
        if nd < min_normal_depth or td < min_tumor_depth:
            continue
        nbaf = n_alt / nd if nd else math.nan
        tbaf = t_alt / td if td else math.nan
        if not (min_normal_baf <= nbaf <= max_normal_baf):
            continue
        ratio = td / nd if nd else math.nan
        if not (ratio > 0 and math.isfinite(ratio)):
            continue
        snp_id = f"{chrom}_{pos}"
        rows.append((snp_id, chrom, int(pos), nd, td, nbaf, tbaf, ratio))

if max_snps and len(rows) > max_snps:
    stride = len(rows) / max_snps
    rows = [rows[int(i * stride)] for i in range(max_snps)]

if len(rows) < 1000:
    raise SystemExit(f"Too few heterozygous SNPs for ASCAT after filtering: {len(rows)}")

ratios = [r[7] for r in rows]
normal_depths = [r[3] for r in rows]
ratio_median = statistics.median(ratios)
normal_median = statistics.median(normal_depths)
paths = {
    "tumor_logr": out / f"{sample}.tumor.LogR.txt",
    "tumor_baf": out / f"{sample}.tumor.BAF.txt",
    "normal_logr": out / f"{sample}.normal.LogR.txt",
    "normal_baf": out / f"{sample}.normal.BAF.txt",
}
handles = {k: v.open("w", encoding="utf-8", newline="") for k, v in paths.items()}
try:
    for h in handles.values():
        h.write(f"SNPid\tchrs\tpos\t{sample}\n")
    for snp_id, chrom, pos, nd, td, nbaf, tbaf, ratio in rows:
        tumor_logr = math.log2(ratio / ratio_median)
        normal_logr = math.log2(nd / normal_median)
        handles["tumor_logr"].write(f"{snp_id}\t{chrom}\t{pos}\t{tumor_logr:.6f}\n")
        handles["tumor_baf"].write(f"{snp_id}\t{chrom}\t{pos}\t{tbaf:.6f}\n")
        handles["normal_logr"].write(f"{snp_id}\t{chrom}\t{pos}\t{normal_logr:.6f}\n")
        handles["normal_baf"].write(f"{snp_id}\t{chrom}\t{pos}\t{nbaf:.6f}\n")
finally:
    for h in handles.values():
        h.close()

summary = out / "ascat_input_summary.tsv"
summary.write_text(
    "metric\tvalue\n"
    f"source_pileup\t{pileup}\n"
    f"sample_id\t{sample}\n"
    f"n_snps\t{len(rows)}\n"
    f"normal_depth_median\t{normal_median:.4f}\n"
    f"tumor_normal_depth_ratio_median\t{ratio_median:.6f}\n"
    f"min_normal_depth\t{min_normal_depth}\n"
    f"min_tumor_depth\t{min_tumor_depth}\n"
    f"normal_baf_range\t{min_normal_baf}-{max_normal_baf}\n"
    f"max_snps\t{max_snps}\n",
    encoding="utf-8",
)
print(summary)
print(f"n_snps={len(rows)} ratio_median={ratio_median:.6f}")
PY

  export PILEUP OUT SAMPLE_ID
  export MIN_NORMAL_DEPTH="${MIN_NORMAL_DEPTH}" MIN_TUMOR_DEPTH="${MIN_TUMOR_DEPTH}"
  export MIN_NORMAL_BAF="${MIN_NORMAL_BAF}" MAX_NORMAL_BAF="${MAX_NORMAL_BAF}" MAX_SNPS="${MAX_SNPS}"
  "${PYTHON_BIN}" "${CONVERT_SCRIPT}"
  date -Is > "${DONE_PILEUP}"
  echo "==> ASCAT pileup(convert) done $(date -Is)"
}

do_fit() {
  [[ -s "${TUMOR_LOGR}" ]] || { echo "ERROR: missing ASCAT inputs; run ASCAT_STEP=pileup first" >&2; exit 1; }
  if [[ -f "${DONE_FIT}" && "${FORCE}" != "1" ]]; then
    echo "==> ASCAT fit already done"
    return 0
  fi
  "${RSCRIPT}" -e 'stopifnot(requireNamespace("ASCAT", quietly=TRUE))'
  ASCAT_R="${OUT}/run_ascat.R"
  cat > "${ASCAT_R}" <<'RS'
suppressPackageStartupMessages(library(ASCAT))
out <- Sys.getenv("OUT")
sample <- Sys.getenv("SAMPLE_ID")
penalty <- as.numeric(Sys.getenv("ASCAT_PENALTY"))
gamma <- as.numeric(Sys.getenv("ASCAT_GAMMA"))
message("Loading ASCAT inputs...")
ascat.obj <- ascat.loadData(
  Tumor_LogR_file = file.path(out, paste0(sample, ".tumor.LogR.txt")),
  Tumor_BAF_file = file.path(out, paste0(sample, ".tumor.BAF.txt")),
  Germline_LogR_file = file.path(out, paste0(sample, ".normal.LogR.txt")),
  Germline_BAF_file = file.path(out, paste0(sample, ".normal.BAF.txt")),
  chrs = as.character(1:22),
  gender = "XX",
  sexchromosomes = c("X", "Y")
)
saveRDS(ascat.obj, file.path(out, paste0(sample, ".ascat.loaded.rds")))
message("Segmenting ASCAT data...")
ascat.obj <- ascat.aspcf(ascat.obj, penalty = penalty, out.dir = out, out.prefix = paste0(sample, "."))
saveRDS(ascat.obj, file.path(out, paste0(sample, ".ascat.segmented.rds")))
message("Running ASCAT purity/ploidy fit...")
ascat.res <- ascat.runAscat(
  ascat.obj,
  gamma = gamma,
  pdfPlot = TRUE,
  img.dir = out,
  img.prefix = paste0(sample, ".")
)
saveRDS(ascat.res, file.path(out, paste0(sample, ".ascat.result.rds")))

extract_one <- function(x, keys) {
  for (k in keys) {
    if (!is.null(x[[k]])) return(x[[k]])
  }
  NA
}
purity <- extract_one(ascat.res, c("aberrantcellfraction", "rho", "purity"))
ploidy <- extract_one(ascat.res, c("ploidy", "psi"))
goodness <- extract_one(ascat.res, c("goodnessOfFit", "goodness"))
summary <- data.frame(
  sample_id = sample,
  purity = paste(purity, collapse = ";"),
  ploidy = paste(ploidy, collapse = ";"),
  goodness = paste(goodness, collapse = ";"),
  gamma = gamma,
  penalty = penalty,
  stringsAsFactors = FALSE
)
write.table(summary, file.path(out, "ascat_summary.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
if (!is.null(ascat.res$segments)) {
  write.table(ascat.res$segments, file.path(out, "ascat_segments.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
}
message("ASCAT done: ", file.path(out, "ascat_summary.tsv"))
RS

  rm -f "${DONE_FIT}"
  export OUT SAMPLE_ID ASCAT_PENALTY ASCAT_GAMMA
  "${RSCRIPT}" "${ASCAT_R}"
  date -Is > "${DONE_FIT}"
  echo "==> ASCAT fit done $(date -Is)"
  cat "${OUT}/ascat_summary.tsv" || true
}

case "${ASCAT_STEP}" in
  pileup) do_pileup ;;
  fit) do_fit ;;
  all) do_pileup; do_fit ;;
  *) echo "ERROR: ASCAT_STEP must be pileup|fit|all" >&2; exit 2 ;;
esac
