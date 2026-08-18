#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

import pandas as pd


COORD_RE = re.compile(r"^(chr(?:[1-9]|1[0-9]|2[0-2]|X|Y)):(\d+)-(\d+)\(([+-])\)$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--statistics", required=True)
    parser.add_argument("--stage0", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    stats = pd.read_csv(args.statistics, sep="\t", index_col=0)
    if "cond" not in stats.columns:
        raise ValueError("SNAF statistics table has no cond column")
    selected = stats[stats["cond"].astype(str).str.lower().isin({"true", "1"})].copy()
    selected.index = selected.index.astype(str)
    selected.index.name = "uid"

    stage0 = pd.read_csv(args.stage0, sep="\t", index_col=0)
    stage0["uid"] = stage0.index.astype(str).str.split(",", n=1).str[0]
    stage0 = stage0.drop_duplicates("uid").set_index("uid")

    merged = selected.join(
        stage0[["coord", "tumor_specificity_mean", "tumor_specificity_mle"]],
        how="left",
    )
    rows = []
    n_swapped = 0
    for uid, row in merged.iterrows():
        match = COORD_RE.match(str(row.get("coord", "")))
        if not match:
            continue
        chrom, start_s, end_s, strand = match.groups()
        start, end = int(start_s), int(end_s)
        # SNAF coord may be donor-acceptor order, not genomic start<=end.
        if start > end:
            start, end = end, start
            n_swapped += 1
        rows.append(
            {
                "chr": chrom,
                "start": start,
                "end": end,
                "strand": strand,
                "uid": uid,
                "snaf_max": row.get("max", ""),
                "snaf_gtex_mean": row.get("mean", ""),
                "snaf_maxmin_diff": row.get("diff", ""),
                "tumor_specificity_mean": row.get("tumor_specificity_mean", ""),
                "tumor_specificity_mle": row.get("tumor_specificity_mle", ""),
            }
        )

    out = pd.DataFrame(rows).drop_duplicates(["chr", "start", "end", "strand"])
    if out.empty:
        raise RuntimeError("No main-chromosome SNAF candidates could be mapped to coordinates")
    out = out.sort_values(["chr", "start", "end", "strand"])
    path = Path(args.out)
    path.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(path, sep="\t", index=False)
    print(f"selected_snaf_uids={len(selected)}")
    print(f"mapped_unique_junctions={len(out)}")
    print(f"coord_start_end_swapped={n_swapped}")
    print(f"output={path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
