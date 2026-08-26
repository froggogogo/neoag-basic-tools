#!/usr/bin/env bash
# =============================================================================
# sunbinbin: build normalized HLA consensus file for neoag (--hla / LOHHLA HLA_FILE)
#
# Project handoff (PRODUCTION_WORKFLOW / production_workflow.example.toml):
#   OptiType + SpecHLA and/or HLA-LA cross-check
#   -> Normalized allele list (one allele per line)
#   -> {CASE_ROOT}/hla/hla_consensus.txt
#
# Rule:
#   - Consensus on HLA-A/B/C at 2-field (A*01:01), majority vote across available tools
#   - Prefer tools that agree; ties break OptiType > HLA-LA > SpecHLA
#   - Class II (DR/DQ/DP…) optional via INCLUDE_CLASS_II=1 (SpecHLA / HLA-LA only)
#
# Usage:
#   bash scripts/build_hla_consensus.sh
#   FORCE=1 INCLUDE_CLASS_II=0 bash scripts/build_hla_consensus.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_ROOT="${CASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

PATIENT_ID="${PATIENT_ID:?export PATIENT_ID}"
NORMAL_SAMPLE_ID="${NORMAL_SAMPLE_ID:-${PATIENT_ID}_blood}"
HLA_ROOT="${HLA_ROOT:-${CASE_ROOT}/hla}"
OUT_DIR="${OUT_DIR:-${HLA_ROOT}}"
OUT_TXT="${OUT_TXT:-${OUT_DIR}/hla_consensus.txt}"
OUT_TSV="${OUT_TSV:-${OUT_DIR}/hla_typing_consensus.tsv}"
OUT_LOG="${OUT_LOG:-${OUT_DIR}/hla_consensus.build.log}"
FORCE="${FORCE:-0}"
INCLUDE_CLASS_II="${INCLUDE_CLASS_II:-0}"
SPECHLA_SCOPE="${SPECHLA_SCOPE:-normal}"

OPTITYPE_RES="${OPTITYPE_RES:-${HLA_ROOT}/optitype/${NORMAL_SAMPLE_ID}_result.tsv}"
SPECHLA_RES="${SPECHLA_RES:-}"
# Prefer SpecHLA G-group then 4-field result
if [[ -z "${SPECHLA_RES}" ]]; then
  for cand in \
    "${HLA_ROOT}/spechla/typing/${SPECHLA_SCOPE}/${NORMAL_SAMPLE_ID}/hla.result.g.group.txt" \
    "${HLA_ROOT}/spechla/typing/${SPECHLA_SCOPE}/${NORMAL_SAMPLE_ID}/hla.result.txt"
  do
    [[ -s "${cand}" ]] && SPECHLA_RES="${cand}" && break
  done
fi
HLALA_RES="${HLALA_RES:-}"
if [[ -z "${HLALA_RES}" ]]; then
  for cand in \
    "${HLA_ROOT}/hla_la/working/${NORMAL_SAMPLE_ID}/hla/R1_bestguess_G.txt" \
    "${HLA_ROOT}/hla_la/working/${NORMAL_SAMPLE_ID}/hla/R1_bestguess.txt"
  do
    [[ -s "${cand}" ]] && HLALA_RES="${cand}" && break
  done
fi

mkdir -p "${OUT_DIR}"
exec > >(tee -a "${OUT_LOG}") 2>&1

ts() { date -Is; }

if [[ -s "${OUT_TXT}" && "${FORCE}" != "1" ]]; then
  echo "==> hla_consensus exists (FORCE=0) -> ${OUT_TXT}"
  cat "${OUT_TXT}"
  exit 0
fi

echo "==> build_hla_consensus $(ts)"
echo "    optitype=${OPTITYPE_RES:-MISSING}"
echo "    spechla=${SPECHLA_RES:-MISSING}"
echo "    hla_la=${HLALA_RES:-MISSING}"
echo "    out_txt=${OUT_TXT}"
echo "    include_class_ii=${INCLUDE_CLASS_II}"

python3 - "${OPTITYPE_RES:-}" "${SPECHLA_RES:-}" "${HLALA_RES:-}" "${OUT_TXT}" "${OUT_TSV}" "${INCLUDE_CLASS_II}" <<'PY'
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

opti_path, spechla_path, hlala_path, out_txt, out_tsv, include_ii = sys.argv[1:7]
include_ii = include_ii == "1"

CLASS_I = ("A", "B", "C")
CLASS_II = ("DRB1", "DQB1", "DPB1", "DQA1", "DPA1")
LOCI = CLASS_I + (CLASS_II if include_ii else ())
TOOL_PRIORITY = {"OptiType": 0, "HLA-LA": 1, "SpecHLA": 2}


def two_field(allele: str) -> str | None:
    a = allele.strip().upper().replace("HLA-", "").replace("HLA_", "")
    a = a.replace("_", "*") if "*" not in a and re.match(r"^[A-Z]+\d", a) else a
    # SpecHLA sometimes HLA_A_1 style headers; allele values like A*01:01:01G
    m = re.search(r"((?:A|B|C|DRB1|DQB1|DPB1|DQA1|DPA1)\*[0-9]{2,3}(?::[0-9A-Za-z]{2,3})+)", a, re.I)
    if not m:
        return None
    raw = m.group(1).upper()
    gene, rest = raw.split("*", 1)
    rest = rest.rstrip("G")  # G-group suffix
    parts = [p for p in rest.split(":") if p]
    if len(parts) < 2:
        return None
    return f"{gene}*{parts[0]}:{parts[1]}"


def locus_of(tf: str) -> str:
    return tf.split("*", 1)[0]


def parse_optitype(path: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = defaultdict(list)
    if not path.is_file() or path.stat().st_size == 0:
        return out
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    if len(lines) < 2:
        return out
    header = lines[0].lstrip("\ufeff").split("\t")
    # OptiType often has leading empty column
    vals = lines[1].split("\t")
    # pad
    while len(vals) < len(header):
        vals.append("")
    row = dict(zip(header, vals))
    for key in ("A1", "A2", "B1", "B2", "C1", "C2"):
        if key not in row or not row[key].strip():
            continue
        tf = two_field(row[key])
        if not tf:
            continue
        loc = locus_of(tf)
        if tf not in out[loc]:
            out[loc].append(tf)
    return out


def parse_spechla(path: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = defaultdict(list)
    if not path.is_file() or path.stat().st_size == 0:
        return out
    lines = [ln for ln in path.read_text(encoding="utf-8", errors="replace").splitlines() if ln and not ln.startswith("#")]
    if len(lines) < 2:
        return out
    header = lines[0].split("\t")
    vals = lines[1].split("\t")
    row = dict(zip(header, vals))
    for h, v in row.items():
        if h.upper() in {"SAMPLE", "SAMPLE_ID"}:
            continue
        # HLA_A_1, HLA_B_2, ...
        m = re.match(r"HLA_([A-Z0-9]+)_([12])$", h, re.I)
        if not m:
            continue
        gene = m.group(1).upper()
        if gene not in LOCI and gene not in CLASS_I + CLASS_II:
            continue
        tf = two_field(v)
        if not tf:
            continue
        loc = locus_of(tf)
        if tf not in out[loc]:
            out[loc].append(tf)
    return out


def parse_hlala(path: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = defaultdict(list)
    if not path.is_file() or path.stat().st_size == 0:
        return out
    # bestguess: Locus Chromosome Allele ...
    for i, ln in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines()):
        if not ln.strip() or ln.startswith("Locus"):
            continue
        cols = ln.split("\t")
        if len(cols) < 3:
            continue
        locus, chrom, allele = cols[0], cols[1], cols[2]
        if locus.upper() not in {*(CLASS_I + CLASS_II)}:
            continue
        # first allele token if semicolon list
        allele = allele.split(";")[0]
        tf = two_field(allele)
        if not tf:
            continue
        loc = locus_of(tf)
        if tf not in out[loc] and len(out[loc]) < 2:
            out[loc].append(tf)
    return out


calls: dict[str, dict[str, list[str]]] = {
    "OptiType": parse_optitype(Path(opti_path)),
    "SpecHLA": parse_spechla(Path(spechla_path)),
    "HLA-LA": parse_hlala(Path(hlala_path)),
}

# per locus: normalized diploid pair (sorted lowres set) from each tool
pairs_by_locus: dict[str, list[tuple[str, frozenset[str]]]] = defaultdict(list)
detail_rows = []
for tool, loci_map in calls.items():
    for loc in LOCI:
        alleles = loci_map.get(loc, [])
        if not alleles:
            continue
        pair = frozenset(alleles[:2])
        pairs_by_locus[loc].append((tool, pair))
        detail_rows.append((tool, loc, " / ".join(sorted(pair))))

consensus_alleles: list[str] = []
tsv_rows: list[str] = ["locus\tconsensus_alleles\tsupport\tstatus\tdetails"]

for loc in LOCI:
    entries = pairs_by_locus.get(loc, [])
    if not entries:
        tsv_rows.append(f"{loc}\t\t0/0\tMISSING\tno tool result")
        continue
    # majority on frozenset pair
    counts: Counter[frozenset[str]] = Counter()
    for tool, pair in entries:
        counts[pair] += 1
    best_pair, best_n = counts.most_common(1)[0]
    n = len(entries)
    if best_n >= 2:
        status = "CONSENSUS"
        chosen = best_pair
    elif n == 1:
        status = "SINGLE_TOOL"
        chosen = best_pair
    else:
        # discordant: pick highest priority tool's pair
        status = "DISCORDANT"
        chosen = None
        for tool, pair in sorted(entries, key=lambda x: TOOL_PRIORITY.get(x[0], 99)):
            chosen = pair
            break
        chosen = chosen or best_pair

    support = f"{best_n}/{n}" if status != "DISCORDANT" else f"{best_n}/{n}"
    details = "; ".join(f"{t}={'/'.join(sorted(p))}" for t, p in entries)
    cons_str = " / ".join(sorted(chosen))
    tsv_rows.append(f"{loc}\t{cons_str}\t{support}\t{status}\t{details}")
    for a in sorted(chosen):
        consensus_alleles.append(f"HLA-{a}")

# dedupe preserve order
seen = set()
final = []
for a in consensus_alleles:
    if a not in seen:
        seen.add(a)
        final.append(a)

Path(out_txt).write_text("\n".join(final) + ("\n" if final else ""), encoding="utf-8")
Path(out_tsv).write_text("\n".join(tsv_rows) + "\n", encoding="utf-8")

print("==> wrote", out_txt)
print("\n".join(final) if final else "(empty)")
print("==> wrote", out_tsv)
for r in tsv_rows[1:]:
    print("   ", r)
if not final:
    sys.exit(1)
# fail soft only if no class I
class_i = [a for a in final if re.match(r"HLA-[ABC]\*", a)]
if len(class_i) < 2:
    print("ERROR: need at least 2 class-I alleles in consensus", file=sys.stderr)
    sys.exit(2)
PY

date -Is > "${OUT_DIR}/.hla_consensus.done"
echo "==> done $(ts); marker ${OUT_DIR}/.hla_consensus.done"
