#!/usr/bin/env bash
# Generic single-sample SpliceMutr patient runner (parameterized; no sample hardcoding).
# Required: SAMPLE, WORK, SNAF_RESULT, HLAS (comma-separated alleles or a text file).
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  SAMPLE=... WORK=... SNAF_RESULT=... HLAS=...|hla.txt [HELPER=...] \
    bash run_splicemutr_patient.sh

  Or positional:
    bash run_splicemutr_patient.sh <SAMPLE> <WORK> <SNAF_RESULT> <HLAS>

Required:
  SAMPLE       Sample ID (written to run_status.tsv)
  WORK         Output directory for this run
  SNAF_RESULT  Directory containing NeoJunction_statistics_maxmin.txt and stage0 frequency table
  HLAS         Comma-separated alleles, or a file with one allele per line

Optional env:
  HELPER, GTF, SPLICEMUTR_HOME, CONDA, ENV, NETMHCPAN, BSGENOME,
  SNAF_STAGE0, SPLICEMUTR_CHUNKS, BSGENOME_WAIT_ROUNDS, BSGENOME_WAIT_SLEEP
EOF
}

# Positional overrides (do not invent sample defaults).
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }
[[ -n "${1:-}" ]] && SAMPLE="$1"
[[ -n "${2:-}" ]] && WORK="$2"
[[ -n "${3:-}" ]] && SNAF_RESULT="$3"
[[ -n "${4:-}" ]] && HLAS="$4"

SAMPLE="${SAMPLE:-}"
WORK="${WORK:-}"
SNAF_RESULT="${SNAF_RESULT:-}"
HLAS="${HLAS:-}"

# Shared refs/tools: neoag-100T. Conda/env: this host only (no 169 env_tool defaults on 66/134).
_DEPS="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
_CONDA_BASE="${NEOAG_CONDA_BASE:-}"
if [[ -z "${_CONDA_BASE}" ]]; then
  _ips=" $(hostname -I 2>/dev/null || true) "
  if [[ "${_ips}" == *" 10.200.65.66 "* ]]; then
    _CONDA_BASE=/root/neo/envs/miniforge3
  elif [[ "${_ips}" == *" 10.200.50.134 "* ]]; then
    _CONDA_BASE=/home/na/miniforge3
  elif [[ "${_ips}" == *" 10.200.65.169 "* ]]; then
    _CONDA_BASE=/root/neo/env_tool/miniforge3
  fi
fi
GTF="${GTF:-${RNA_GTF:-${_DEPS}/refs/ctat/current/ctat_genome_lib_build_dir/ref_annot.gtf}}"
SPLICEMUTR_HOME="${SPLICEMUTR_HOME:-${_DEPS}/tools/SpliceMutr}"
if [[ ! -d "${SPLICEMUTR_HOME}/Rscripts" ]]; then
  case "$(hostname -I 2>/dev/null || true)" in
    *10.200.65.66*) SPLICEMUTR_HOME="${SPLICEMUTR_HOME:-/root/neo/envs/tools/SpliceMutr}" ;;
    *10.200.65.169*) SPLICEMUTR_HOME="${SPLICEMUTR_HOME:-/root/neo/env_tool/tools/SpliceMutr}" ;;
  esac
fi
CONDA="${CONDA:-${_CONDA_BASE}/bin/conda}"
ENV="${ENV:-${_CONDA_BASE}/envs/neoag-splicemutr}"
NETMHCPAN="${NETMHCPAN:-${_DEPS}/licenses/predictors/netMHCpan/netMHCpan}"
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${HELPER:-${_SCRIPT_DIR}/prepare_splicemutr_candidates.py}"
BSGENOME="${BSGENOME:-BSgenome.Hsapiens.UCSC.hg38}"
SNAF_STAGE0="${SNAF_STAGE0:-frequency_stage0_verbosity1_uid_gene_symbol_coord_mean_mle.txt}"
CHUNKS="${SPLICEMUTR_CHUNKS:-4}"
BSGENOME_WAIT_ROUNDS="${BSGENOME_WAIT_ROUNDS:-120}"
BSGENOME_WAIT_SLEEP="${BSGENOME_WAIT_SLEEP:-30}"

require_nonempty() {
  local name="$1" value="$2"
  if [[ -z "$value" ]]; then
    echo "ERROR: $name is required (set env or pass positional arg)" >&2
    usage >&2
    exit 1
  fi
}

require_nonempty SAMPLE "$SAMPLE"
require_nonempty WORK "$WORK"
require_nonempty SNAF_RESULT "$SNAF_RESULT"
require_nonempty HLAS "$HLAS"

# HLAS may be a file (one allele per line) or an already comma-separated string.
resolve_hlas() {
  local raw="$1"
  local alleles=()
  local line cleaned
  if [[ -f "$raw" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      [[ -z "$line" || "$line" == \#* ]] && continue
      # Allow comma/semicolon packed lines inside a file as well.
      line="${line//;/,}"
      IFS=',' read -r -a parts <<<"$line"
      for cleaned in "${parts[@]}"; do
        cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"
        cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
        [[ -z "$cleaned" ]] && continue
        cleaned="${cleaned//\*/}"
        alleles+=("$cleaned")
      done
    done <"$raw"
  else
    raw="${raw//;/,}"
    IFS=',' read -r -a parts <<<"$raw"
    for cleaned in "${parts[@]}"; do
      cleaned="${cleaned#"${cleaned%%[![:space:]]*}"}"
      cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"
      [[ -z "$cleaned" ]] && continue
      cleaned="${cleaned//\*/}"
      alleles+=("$cleaned")
    done
  fi
  if [[ "${#alleles[@]}" -eq 0 ]]; then
    echo "ERROR: no HLA alleles parsed from HLAS=$raw" >&2
    exit 2
  fi
  local IFS=,
  printf '%s' "${alleles[*]}"
}

HLAS_RESOLVED="$(resolve_hlas "$HLAS")"

INPUT="$WORK/input"
REF="$WORK/reference"
FORMED="$WORK/formed_transcripts"
COMBINED="$WORK/combined"
PEPTIDES="$WORK/peptides"
PRESENTATION="$WORK/presentation"
LOGS="$WORK/logs"
mkdir -p "$INPUT" "$REF" "$FORMED" "$COMBINED" "$PEPTIDES" "$PRESENTATION" "$LOGS"

exec > >(tee -a "$LOGS/driver.log") 2>&1
echo "[$(date '+%F %T')] SpliceMutr patient run starts"
echo "SAMPLE=$SAMPLE"
echo "WORK=$WORK"
echo "SNAF_RESULT=$SNAF_RESULT"
echo "HLAS_RESOLVED=$HLAS_RESOLVED"
echo "HELPER=$HELPER"
echo "ENV=$ENV"
echo "SPLICEMUTR_HOME=$SPLICEMUTR_HOME"

STATS="$SNAF_RESULT/NeoJunction_statistics_maxmin.txt"
STAGE0="$SNAF_RESULT/$SNAF_STAGE0"
test -s "$STATS" || { echo "ERROR: missing SNAF statistics: $STATS" >&2; exit 3; }
test -s "$STAGE0" || { echo "ERROR: missing SNAF stage0 table: $STAGE0" >&2; exit 3; }
test -s "$GTF" || { echo "ERROR: missing GTF: $GTF" >&2; exit 3; }
test -x "$NETMHCPAN" || { echo "ERROR: NetMHCpan not executable: $NETMHCPAN" >&2; exit 3; }
test -x "$ENV/bin/python" || { echo "ERROR: python missing in ENV: $ENV" >&2; exit 3; }
test -f "$HELPER" || { echo "ERROR: HELPER not found: $HELPER" >&2; exit 3; }
test -d "$SPLICEMUTR_HOME/Rscripts" || { echo "ERROR: invalid SPLICEMUTR_HOME: $SPLICEMUTR_HOME" >&2; exit 3; }

CANDIDATES="$INPUT/snaf_maxmin_junctions.tsv"
INTRONS="$INPUT/snaf_maxmin_junctions.rds"
if [[ ! -s "$INTRONS" ]]; then
  "$ENV/bin/python" "$HELPER" \
    --statistics "$STATS" \
    --stage0 "$STAGE0" \
    --out "$CANDIDATES"
  "$CONDA" run --no-capture-output -p "$ENV" Rscript -e \
    'x <- read.delim(commandArgs(TRUE)[1], check.names=FALSE); saveRDS(x[,c("chr","start","end","strand")], commandArgs(TRUE)[2])' \
    "$CANDIDATES" "$INTRONS"
  test -s "$INTRONS"
fi

echo "[$(date '+%F %T')] Waiting for BSgenome"
bsgenome_ready=0
for _ in $(seq 1 "$BSGENOME_WAIT_ROUNDS"); do
  if "$CONDA" run --no-capture-output -p "$ENV" Rscript -e \
      'pkg <- commandArgs(TRUE)[1]; quit(status=ifelse(requireNamespace(pkg, quietly=TRUE), 0, 1))' \
      "$BSGENOME"; then
    bsgenome_ready=1
    break
  fi
  sleep "$BSGENOME_WAIT_SLEEP"
done
if [[ "$bsgenome_ready" != "1" ]]; then
  echo "ERROR: BSgenome did not become available: $BSGENOME" >&2
  exit 31
fi
"$CONDA" run --no-capture-output -p "$ENV" Rscript -e \
  'pkg <- commandArgs(TRUE)[1]; suppressPackageStartupMessages(library(pkg, character.only=TRUE)); cat("BSgenome ready\n")' \
  "$BSGENOME"

TXDB="$REF/gencode_txdb.sqlite"
if [[ ! -s "$TXDB" ]]; then
  echo "[$(date '+%F %T')] Building TxDb"
  "$CONDA" run --no-capture-output -p "$ENV" Rscript \
    "$SPLICEMUTR_HOME/Rscripts/make_txdb.R" -o "$TXDB" -g "$GTF"
  test -s "$TXDB"
fi

TXDB_UCSC_MARKER="$REF/.gencode_txdb_ucsc_names"
if ! "$CONDA" run --no-capture-output -p "$ENV" Rscript -e \
    'suppressPackageStartupMessages(library(GenomicFeatures)); tx <- loadDb(commandArgs(TRUE)[1]); g <- genes(tx); quit(status=ifelse("chr1" %in% seqlevels(tx) && any(as.character(seqnames(g)) == "chr1"), 0, 1))' \
    "$TXDB"; then
  echo "[$(date '+%F %T')] Harmonizing TxDb sequence names with UCSC BSgenome"
  "$CONDA" run --no-capture-output -p "$ENV" Rscript -e \
    'suppressPackageStartupMessages({library(DBI); library(RSQLite)}); p <- commandArgs(TRUE)[1]; con <- dbConnect(SQLite(), p); on.exit(dbDisconnect(con)); primary <- c(as.character(1:22), "X", "Y"); placeholders <- paste(rep("?", length(primary)), collapse=","); specs <- list(c("chrominfo","chrom"), c("transcript","tx_chrom"), c("exon","exon_chrom"), c("cds","cds_chrom")); for (spec in specs) { dbExecute(con, sprintf("UPDATE %s SET %s = ? || %s WHERE %s IN (%s)", spec[1], spec[2], spec[2], spec[2], placeholders), params=as.list(c("chr", primary))); dbExecute(con, sprintf("UPDATE %s SET %s = ? WHERE %s = ?", spec[1], spec[2], spec[2]), params=list("chrM", "MT")); }' \
    "$TXDB"
  "$CONDA" run --no-capture-output -p "$ENV" Rscript -e \
    'suppressPackageStartupMessages(library(GenomicFeatures)); tx <- loadDb(commandArgs(TRUE)[1]); g <- genes(tx); stopifnot("chr1" %in% seqlevels(tx), "chrX" %in% seqlevels(tx), any(as.character(seqnames(g)) == "chr1")); cat(paste(head(seqlevels(tx)), collapse=","), "\n")' \
    "$TXDB"
  printf 'TxDb seqlevelsStyle=UCSC\n' > "$TXDB_UCSC_MARKER"
fi

CHUNK_INPUT="$INPUT/chunks_${CHUNKS}"
CHUNK_FORMED="$FORMED/chunks_${CHUNKS}"
mkdir -p "$CHUNK_INPUT" "$CHUNK_FORMED"

if [[ "$(find "$CHUNK_INPUT" -maxdepth 1 -name 'chunk_*.rds' -type f | wc -l)" -ne "$CHUNKS" ]]; then
  echo "[$(date '+%F %T')] Splitting junctions into $CHUNKS deterministic chunks"
  "$CONDA" run --no-capture-output -p "$ENV" Rscript -e \
    'a <- commandArgs(TRUE); x <- readRDS(a[1]); out <- a[2]; n <- as.integer(a[3]); groups <- cut(seq_len(nrow(x)), breaks=n, labels=FALSE); for (i in seq_len(n)) saveRDS(x[groups == i,,drop=FALSE], file.path(out, sprintf("chunk_%02d.rds", i)))' \
    "$INTRONS" "$CHUNK_INPUT" "$CHUNKS"
fi

echo "[$(date '+%F %T')] Reconstructing SpliceMutr transcripts in $CHUNKS parallel chunks"
form_pids=()
form_labels=()
for i in $(seq 1 "$CHUNKS"); do
  idx=$(printf '%02d' "$i")
  chunk="$CHUNK_INPUT/chunk_${idx}.rds"
  prefix="$CHUNK_FORMED/snaf_maxmin_chunk_${idx}"
  formed_rds="${prefix}_data_splicemutr.rds"
  formed_fasta="${prefix}_sequences.fa"
  if [[ -s "$formed_rds" && -s "$formed_fasta" ]]; then
    continue
  fi
  "$CONDA" run --no-capture-output -p "$ENV" Rscript \
    "$SPLICEMUTR_HOME/Rscripts/form_transcripts.R" \
    -o "$prefix" -t "$TXDB" -j "$chunk" -b "$BSGENOME" \
    -f "$SPLICEMUTR_HOME/Rfunctions/functions.R" \
    >"$LOGS/form_transcripts_chunk_${idx}.log" 2>&1 &
  form_pids+=("$!")
  form_labels+=("$idx")
done
for j in "${!form_pids[@]}"; do
  if ! wait "${form_pids[$j]}"; then
    echo "ERROR: form_transcripts failed for chunk ${form_labels[$j]}" >&2
    exit 41
  fi
done

echo "[$(date '+%F %T')] Calculating coding potential in $CHUNKS parallel chunks"
cp_pids=()
cp_labels=()
for i in $(seq 1 "$CHUNKS"); do
  idx=$(printf '%02d' "$i")
  prefix="$CHUNK_FORMED/snaf_maxmin_chunk_${idx}"
  formed_rds="${prefix}_data_splicemutr.rds"
  formed_fasta="${prefix}_sequences.fa"
  cp_rds="${prefix}_data_splicemutr_cp_corrected.rds"
  test -s "$formed_rds"
  test -s "$formed_fasta"
  if [[ -s "$cp_rds" ]]; then
    continue
  fi
  "$CONDA" run --no-capture-output -p "$ENV" Rscript \
    "$SPLICEMUTR_HOME/Rscripts/calc_coding_potential.R" \
    -o "$CHUNK_FORMED" -s "$formed_rds" -t "$formed_fasta" \
    -f "$SPLICEMUTR_HOME/Rfunctions/functions.R" \
    >"$LOGS/coding_potential_chunk_${idx}.log" 2>&1 &
  cp_pids+=("$!")
  cp_labels+=("$idx")
done
for j in "${!cp_pids[@]}"; do
  if ! wait "${cp_pids[$j]}"; then
    echo "ERROR: coding potential failed for chunk ${cp_labels[$j]}" >&2
    exit 42
  fi
done

# SpliceMutr dispatches list-vs-single-RDS input by filename extension.
CP_LIST="$COMBINED/splicemutr_cp_rds.txt"
: > "$CP_LIST"
for i in $(seq 1 "$CHUNKS"); do
  idx=$(printf '%02d' "$i")
  cp_rds="$CHUNK_FORMED/snaf_maxmin_chunk_${idx}_data_splicemutr_cp_corrected.rds"
  test -s "$cp_rds"
  printf '%s\n' "$cp_rds" >> "$CP_LIST"
done

PROTEINS="$COMBINED/proteins.txt"
if [[ ! -s "$PROTEINS" ]]; then
  echo "[$(date '+%F %T')] Combining reconstructed proteins"
  "$CONDA" run --no-capture-output -p "$ENV" Rscript \
    "$SPLICEMUTR_HOME/Rscripts/combine_splicemutr.R" \
    -o "$COMBINED" -s "$CP_LIST"
  test -s "$PROTEINS"
fi

KMERS="$PEPTIDES/peps_9.txt"
if [[ ! -s "$KMERS" ]]; then
  echo "[$(date '+%F %T')] Generating unique 9-mers"
  PYTHONPATH="$SPLICEMUTR_HOME/python_scripts${PYTHONPATH:+:$PYTHONPATH}" \
    "$ENV/bin/python" "$SPLICEMUTR_HOME/python_scripts/process_peptides.py" \
    -p "$PROTEINS" -o "$PEPTIDES" -k 9
  test -s "$KMERS"
fi

XLS="$PRESENTATION/netmhcpan_4.2c.xls"
if [[ ! -s "$XLS" ]]; then
  echo "[$(date '+%F %T')] Running NetMHCpan for $HLAS_RESOLVED"
  "$NETMHCPAN" -p "$KMERS" -a "$HLAS_RESOLVED" -l 9 -xls -xlsfile "$XLS" \
    >"$PRESENTATION/netmhcpan.stdout.txt" 2>&1
  test -s "$XLS"
fi

cat > "$WORK/run_status.tsv" <<EOF
field	value
sample_id	$SAMPLE
splice_junction_source	SNAF_maxmin_GTEx_filtered
splicemutr_transcript_reconstruction	ASSESSED
splicemutr_peptide_generation	ASSESSED
presentation_prediction	NetMHCpan_4.2c
cohort_antigenicity_metric	UNASSESSED_SINGLE_SAMPLE
cohort_antigenicity_reason	LeafCutter cohort/outlier background not available for one WTS sample
hla_alleles	$HLAS_RESOLVED
EOF

touch "$WORK/.splicemutr_patient_complete"
echo "[$(date '+%F %T')] SpliceMutr patient run complete"
