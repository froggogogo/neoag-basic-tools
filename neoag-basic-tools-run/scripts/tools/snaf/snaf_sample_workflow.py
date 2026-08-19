#!/usr/bin/env python3
from __future__ import annotations

import csv
import os
import re
from pathlib import Path

import pandas as pd
import snaf

COORD_RE = re.compile(r"^([^:]+):(\d+)-(\d+)(\([+-]\))?$")


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


def read_hla(path: Path) -> list[str]:
    values: list[str] = []
    for token in path.read_text(encoding="utf-8").replace(",", "\n").splitlines():
        allele = token.strip()
        if allele and allele.startswith("HLA-"):
            values.append(allele)
    if not values:
        raise RuntimeError(f"no HLA class-I alleles found in {path}")
    return values


def _results_all_none(jcmq) -> bool:
    results = getattr(jcmq, "results", None)
    if not results or not isinstance(results, tuple) or not results:
        return True
    first = results[0]
    if not isinstance(first, list) or not first:
        return True
    return all(item is None for item in first)


def rewrite_coord_string(coord: str) -> tuple[str, bool]:
    """Force genomic start-end order: chrN:start-end(strand) with start<=end."""
    text = str(coord).strip()
    match = COORD_RE.match(text)
    if not match:
        return str(coord), False
    chrom, start_s, end_s, strand = match.groups()
    start_i, end_i = int(start_s), int(end_s)
    if start_i <= end_i:
        return text, False
    return f"{chrom}:{end_i}-{start_i}{strand or ''}", True


def genomic_span(coord: str) -> tuple[str, str, str, bool]:
    """Parse SNAF coord and return chrom, genomic start, end (start<=end)."""
    rewritten, swapped = rewrite_coord_string(coord)
    chrom = rewritten.split(":", 1)[0] if ":" in rewritten else ""
    span = rewritten.split(":", 1)[1].split("(", 1)[0] if ":" in rewritten else ""
    start, end = (span.split("-", 1) + [""])[:2] if span else ("", "")
    return chrom, start, end, swapped


def rewrite_coord_column(path: Path) -> int:
    if not path.is_file() or path.stat().st_size == 0:
        return 0
    with path.open(encoding="utf-8", errors="replace", newline="") as handle:
        rows = [line.rstrip("\n").split("\t") for line in handle]
    if not rows:
        return 0
    try:
        idx = next(i for i, name in enumerate(rows[0]) if name.strip().lower() == "coord")
    except StopIteration:
        return 0
    n_swapped = 0
    for row in rows[1:]:
        if len(row) <= idx:
            continue
        new_value, swapped = rewrite_coord_string(row[idx])
        n_swapped += int(swapped)
        row[idx] = new_value
    if n_swapped:
        with path.open("w", encoding="utf-8", newline="") as handle:
            for row in rows:
                handle.write("\t".join(row) + "\n")
    return n_swapped


def normalize_snaf_coord_tables(outdir: Path) -> None:
    targets = [
        outdir / "frequency_stage0_verbosity1_uid_gene_symbol_coord_mean_mle.txt",
        outdir / "T_candidates" / "T_antigen_candidates_all.txt",
    ]
    targets.extend(sorted((outdir / "T_candidates").glob("T_antigen_candidates_*.txt")))
    seen: set[Path] = set()
    for path in targets:
        if path in seen:
            continue
        seen.add(path)
        n_swapped = rewrite_coord_column(path)
        if n_swapped:
            print(f"normalized coord start<=end in {path} swapped={n_swapped}", flush=True)


def main() -> int:
    # Ensure netMHCpan helper wrappers can find conda sysroot.
    os.environ.setdefault("NEOAG_CONDA_BASE", "/home/na/miniforge3")

    outdir = Path(required_env("NEOAG_SNAF_OUTDIR"))
    matrix_path = Path(required_env("NEOAG_SNAF_MATRIX"))
    db_dir = Path(required_env("NEOAG_SNAF_DB"))
    hla_file = Path(required_env("NEOAG_SNAF_HLA_FILE"))
    sample_id = required_env("NEOAG_SNAF_SAMPLE_ID")
    cores = int(os.environ.get("NEOAG_SNAF_CORES", "8"))
    netmhcpan = os.environ.get("NEOAG_NETMHCPAN_BIN") or None
    binding_method = os.environ.get(
        "NEOAG_SNAF_BINDING_METHOD", "netMHCpan" if netmhcpan else "MHCflurry"
    )
    force_rebind = os.environ.get("NEOAG_SNAF_FORCE_REBIND", "0") == "1"

    expected = [
        db_dir / "Alt91_db/Hs_Ensembl_exon_add_col.txt",
        db_dir / "Alt91_db/mRNA-ExonIDs.txt",
        db_dir / "Alt91_db/Hs_gene-seq-2000_flank.fa",
        db_dir / "controls/GTEx_junction_counts.h5ad",
    ]
    missing = [str(path) for path in expected if not path.is_file()]
    if missing:
        raise RuntimeError("incomplete SNAF reference: " + ", ".join(missing))

    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "assets").mkdir(exist_ok=True)
    # Also satisfy snaf dash_app atexit cwd edge-cases.
    Path("assets").mkdir(exist_ok=True)

    df = pd.read_csv(matrix_path, sep="\t", index_col=0)
    if df.empty or df.shape[0] == 0:
        raise RuntimeError(
            f"SNAF matrix is empty: {matrix_path}. "
            "Use counts.original.full.txt / altanalyze_counts.snaf_input.tsv "
            "(EventAnnotation pruned matrix is often empty for single-sample)."
        )
    candidates = [column for column in df.columns if "replicate" not in str(column).lower()]
    if not candidates:
        raise RuntimeError(f"no primary sample column found in {matrix_path}")
    df = df.loc[:, [candidates[0]]]
    df.columns = [sample_id]
    df.index = [str(i).split("=", 1)[0] for i in df.index]
    df = df.loc[~df.index.duplicated(keep="first")]
    df = df.loc[(df.fillna(0) > 0).any(axis=1)]
    if df.empty:
        raise RuntimeError(f"SNAF matrix has no non-zero junctions: {matrix_path}")
    df.to_csv(outdir / "snaf_junction_count_matrix.tsv", sep="\t")
    print(f"SNAF matrix ready: {df.shape[0]} junctions x {df.shape[1]} samples", flush=True)

    hlas = read_hla(hla_file)
    if binding_method.lower() == "netmhcpan" and not netmhcpan:
        raise RuntimeError("NEOAG_NETMHCPAN_BIN is required for SNAF NetMHCpan mode")
    snaf.initialize(
        df=df,
        db_dir=str(db_dir),
        gtex_mode="count",
        binding_method=binding_method,
        software_path=netmhcpan,
    )

    pickle_path = outdir / "after_prediction.p"
    resumed = False
    if pickle_path.is_file():
        jcmq = snaf.JunctionCountMatrixQuery.deserialize(name=str(pickle_path))
        translated = getattr(jcmq, "translated", None) or []
        if translated and (_results_all_none(jcmq) or force_rebind):
            print(
                f"Resuming SNAF binding/immunogenicity on {len(translated)} translated NeoJunctions "
                f"(prior results empty/None; netMHCpan rebind)",
                flush=True,
            )
            jcmq.cores = cores
            jcmq.parallelize_run(kind=3, hlas=[hlas])
            jcmq.serialize(outdir=str(outdir), name="after_prediction.p")
            resumed = True
        elif not _results_all_none(jcmq):
            print("Reusing existing after_prediction.p with non-empty binding results", flush=True)
            resumed = True

    if not resumed:
        query = snaf.JunctionCountMatrixQuery(
            junction_count_matrix=df,
            cores=cores,
            outdir=str(outdir),
            filter_mode="maxmin",
        )
        query.run(hlas=[hlas], outdir=str(outdir))

    snaf.JunctionCountMatrixQuery.generate_results(
        path=str(outdir / "after_prediction.p"), outdir=str(outdir)
    )
    normalize_snaf_coord_tables(outdir)

    source = outdir / "T_candidates" / f"T_antigen_candidates_{sample_id}.txt"
    if not source.is_file():
        source = outdir / "T_candidates" / "T_antigen_candidates_all.txt"
    fields = [
        "sample_id", "event_id", "gene", "chrom", "start", "end",
        "junction_reads", "peptide", "hla_allele", "binding_rank",
        "immunogenicity", "tumor_specificity_mean", "tumor_specificity_mle",
        "source_tool", "evidence_status",
    ]
    output = outdir / "snaf_candidates.tsv"
    rows: list[dict] = []
    n_swapped = 0
    if source.is_file() and source.stat().st_size > 0:
        with source.open(encoding="utf-8", errors="replace", newline="") as handle:
            rows = list(csv.DictReader(handle, delimiter="\t"))
    else:
        print(
            f"WARNING: no T-antigen candidate table at {source}; writing empty snaf_candidates.tsv",
            flush=True,
        )
        (outdir / "T_candidates").mkdir(exist_ok=True)
        empty = outdir / "T_candidates" / f"T_antigen_candidates_{sample_id}.txt"
        if not empty.is_file():
            empty.write_text("\t".join(["peptide", "uid", "symbol", "coord"]) + "\n", encoding="utf-8")

    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        for row in rows:
            coord = str(row.get("coord", ""))
            chrom, start, end, swapped = genomic_span(coord)
            if swapped:
                n_swapped += 1
            writer.writerow({
                "sample_id": sample_id,
                "event_id": row.get("uid", ""),
                "gene": row.get("symbol", ""),
                "chrom": chrom,
                "start": start,
                "end": end,
                "junction_reads": row.get("junction_count", ""),
                "peptide": row.get("peptide", ""),
                "hla_allele": row.get("hla", ""),
                "binding_rank": row.get("binding_affinity", ""),
                "immunogenicity": row.get("immunogenicity", ""),
                "tumor_specificity_mean": row.get("tumor_specificity_mean", ""),
                "tumor_specificity_mle": row.get("tumor_specificity_mle", ""),
                "source_tool": "SNAF",
                "evidence_status": "SNAF_GTEX_SUPPORTED",
            })
    print(f"wrote {output} rows={len(rows)} coord_start_end_swapped={n_swapped}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
