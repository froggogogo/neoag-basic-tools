#!/usr/bin/env python3
"""pVACsplice entry: strip GTF gene_id versions so they match VEP ENSG IDs.

CTAT/ref_annot.gtf uses ENSG00000165416.15; VEP TSV uses ENSG00000165416.
pVACsplice CombineInputs inner-joins on gene_id+transcript_id+version+variant_info
and aborts with "Combined dataset is empty" when they disagree.

Usage: same argv as `pvacsplice run` (do NOT pass the subcommand `run`).
"""
import sys
from pvactools.lib import combine_inputs as ci
from pvactools.tools.pvacsplice import run as pvacsplice_run

_orig = ci.CombineInputs.merge_and_write


def _strip_gene_version(df):
    if df is not None and "gene_id" in df.columns:
        df = df.copy()
        df["gene_id"] = df["gene_id"].astype(str).str.replace(r"\.\d+$", "", regex=True)
    return df


def merge_and_write(self, j_df, var_df):
    return _orig(self, _strip_gene_version(j_df), _strip_gene_version(var_df))


ci.CombineInputs.merge_and_write = merge_and_write
pvacsplice_run.main(sys.argv[1:])
