#!/usr/bin/env python3
"""sequenza-utils bam2seqz wrapper: avoid c_pileup ValueError: embedded null character.

sunbinbin crashed in sequenza.c_pileup.acgt / do_seqz when samtools 1.23
mpileup emitted NUL bytes. This wrapper:
  1) forces the pure-Python acgt parser
  2) strips/replaces NULs in pileup/quality strings
  3) decodes mpileup stdout as latin-1 (not utf-8)

Prefer samtools 1.9 for mpileup (-S). See references/runtime-hardening.md.
"""
from __future__ import annotations

import sys

from sequenza.pileup import acgt as py_acgt
import sequenza.samtools as sequenza_samtools
import sequenza.seqz as sequenza_seqz


def acgt_nulsafe(pileup, quality, depth, reference, qlimit=53, noend=False, nostart=False):
    if pileup is None:
        pileup = ""
    if quality is None:
        quality = ""
    if isinstance(pileup, bytes):
        pileup = pileup.decode("latin-1")
    if isinstance(quality, bytes):
        quality = quality.decode("latin-1")
    pileup = pileup.replace("\x00", "*")
    quality = quality.replace("\x00", "!")
    return py_acgt(pileup, quality, depth, reference, qlimit, noend=noend, nostart=nostart)


def _iter_latin1(self):
    while True:
        try:
            raw = next(self.proc2.stdout)
        except StopIteration:
            break
        yield raw.decode("latin-1")


sequenza_seqz.acgt = acgt_nulsafe
sequenza_samtools.bam_mpileup.__iter__ = _iter_latin1

from sequenza.commands import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main() or 0)
