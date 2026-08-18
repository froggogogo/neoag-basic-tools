#!/usr/bin/env python3
"""Patch neo sarcoma profiles with IEDB fallback-only immunogenicity."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

IMMUNO_BLOCK = """[immunogenicity]
enabled = true
sources = ["prime", "bigmhc_im", "deepimmuno"]
composite = "mean"
use_iedb_fallback = true

[immunogenicity.weights]
prime = 0.35
bigmhc_im = 0.35
deepimmuno = 0.30
"""

SECTION_RE = re.compile(
    r"\[immunogenicity\][\s\S]*?(?=\[(?!immunogenicity\.weights\])|\Z)",
    re.M,
)

DEFAULT_PROFILES = (
    "profiles/sarcoma_rna_supported_v2_provisional.toml",
    "profiles/sarcoma_rna_supported.toml",
)


def patch_text(text: str) -> str:
    replacement = IMMUNO_BLOCK.rstrip() + "\n\n"
    if SECTION_RE.search(text):
        return SECTION_RE.sub(replacement, text, count=1)
    return text.rstrip() + "\n\n" + IMMUNO_BLOCK


def patch_file(path: Path, *, backup: bool) -> str:
    original = path.read_text(encoding="utf-8")
    updated = patch_text(original)
    if updated == original:
        return "unchanged"
    if backup:
        bak = path.with_name(path.name + datetime.now().strftime(".bak_%Y%m%d_%H%M%S"))
        shutil.copy2(path, bak)
    path.write_text(updated, encoding="utf-8")
    return "patched"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--neo-root", required=True)
    ap.add_argument("--no-backup", action="store_true")
    args = ap.parse_args()
    root = Path(args.neo_root)
    if not root.is_dir():
        print(f"NEO_ROOT missing: {root}", file=sys.stderr)
        return 1
    status = 0
    for rel in DEFAULT_PROFILES:
        path = root / rel
        if not path.is_file():
            print(f"SKIP {rel} (not found)")
            continue
        result = patch_file(path, backup=not args.no_backup)
        print(f"{result}\t{path}")
        if result == "patched":
            status = 0
    return status


if __name__ == "__main__":
    raise SystemExit(main())
