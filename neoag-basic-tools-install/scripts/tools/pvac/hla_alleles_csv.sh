#!/usr/bin/env bash
# Emit comma-separated HLA alleles from hla_consensus.txt (skip headers like netMHCpan).
set -euo pipefail
HLA_FILE="${1:?usage: hla_alleles_csv.sh HLA_FILE}"
[[ -s "${HLA_FILE}" ]] || { echo "ERROR: missing HLA file: ${HLA_FILE}" >&2; exit 1; }
awk '
  BEGIN{IGNORECASE=1}
  /^[[:space:]]*#/ {next}
  /^[[:space:]]*$/ {next}
  $0 ~ /netmhc|allele|hla_type|sample/ && $0 !~ /^HLA-/ {next}
  {
    line=$0
    gsub(/;.*/, "", line)
    gsub(/[[:space:]]+/, "", line)
    if (line ~ /^HLA-[ABC]\*/) {
      if (out!="") out=out ","
      out=out line
    }
  }
  END{ if (out=="") { print "ERROR: no HLA-A/B/C alleles in " FILENAME > "/dev/stderr"; exit 2 } print out }
' "${HLA_FILE}"
