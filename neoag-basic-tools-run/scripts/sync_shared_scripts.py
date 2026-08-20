#!/usr/bin/env python3
"""Sync sunbinbin gold scripts → NAS shared_scripts (66/134/169).

Outputs:
  shared_scripts/case_templates/       DNA orchestrators + libs
  shared_scripts/short_rna_templates/ per-tool RNA wrappers + inputs.env.sh.template
  shared_scripts/sequenza/             pileup/fit runner + helpers
  shared_scripts/rna/                  built-in master orchestrator
  shared_scripts/snaf/                 (refresh from sunbinbin ops if present)
  shared_scripts/splicemutr/           (already generic)

Patches:
  - NEOAG_ROOT hardcode → lib_portable_env.sh
  - CASE_ROOT overridable via env
  - sunbinbin zjl BAM/VCF defaults → empty (must export or set in case inputs)
  - orchestrators call generic *.sh names in same dir
"""
from __future__ import annotations

import re
import shutil
import stat
from pathlib import Path

ROOT = Path("/mnt/zzbnew/peixunban/gl/mjx/neoag")
SUN_DNA = ROOT / "sunbinbin/scripts"
SUN_RNA = ROOT / "sunbinbin/short-rna/scripts"
SHARED = ROOT / "shared_scripts"
DEPS = Path("/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps")

# When run on NAS host: place skill artifacts beside this script (see deploy step).
_SKILL_ROOT = Path(__file__).resolve().parent
if (_SKILL_ROOT / "run_short_rna_master.sh").is_file():
    SKILL_RNA = _SKILL_ROOT
    SKILL_SEQ = _SKILL_ROOT
    SKILL_SNaf = _SKILL_ROOT
else:
    SKILL_RUN = _SKILL_ROOT
    SKILL_RNA = SKILL_RUN / "tools/rna"
    SKILL_SEQ = SKILL_RUN / "tools/sequenza"
    SKILL_SNaf = SKILL_RUN / "tools/snaf"

PORTABLE_ENV = DEPS / "tools/run/lib/portable_env.sh"
if not PORTABLE_ENV.is_file():
    PORTABLE_ENV = SKILL_RUN / "lib/portable_env.sh"

HARDCODE_BLOCK = re.compile(
    r'NEOAG_ROOT="\$\{NEOAG_ROOT:-/home/na/project/neoantigen/neoag_event_pipeline_v03_rc\}"\s*\n'
    r'(?:# shellcheck source=/dev/null\s*\n)?'
    r'source "\$\{NEOAG_ROOT\}/conf/tools\.env\.sh"\s*\n'
    r'\[\[ -f "\$\{NEOAG_ROOT\}/conf/tools\.env\.local\.sh" \]\] && source "\$\{NEOAG_ROOT\}/conf/tools\.env\.local\.sh"\s*\n',
    re.M,
)

CASE_ROOT_RE = re.compile(
    r'^CASE_ROOT="\$\(cd "\$\{SCRIPT_DIR\}/\.\." && pwd\)"$',
    re.M,
)

SHORT_RNA_ROOT_RE = re.compile(
    r'^SHORT_RNA_ROOT="\$\(cd "\$\{SCRIPT_DIR\}/\.\." && pwd\)"$',
    re.M,
)

PORTABLE_SNIPPET = (
    '# Portable env (66/134/169): resolve NEOAG_ROOT without hardcoding 134 paths\n'
    '# shellcheck source=/dev/null\n'
    'source "${SCRIPT_DIR}/lib_portable_env.sh"\n'
)

SUNBINBIN_BAM_DEFAULTS = [
    (
        'TUMOR_BAM="${TUMOR_BAM:-/mnt/zjl-bgi-zzb/peixunban/gl/data/chenxiaoliang_data/dsrct_data/dsrct/sunbinbin/wgs/sunbinbin_tumor.align.bam}"',
        'TUMOR_BAM="${TUMOR_BAM:?export TUMOR_BAM}"',
    ),
    (
        'NORMAL_BAM="${NORMAL_BAM:-/mnt/zjl-bgi-zzb/peixunban/gl/data/chenxiaoliang_data/dsrct_data/dsrct/sunbinbin/wgs/sunbinbin_blood.align.bam}"',
        'NORMAL_BAM="${NORMAL_BAM:?export NORMAL_BAM}"',
    ),
    (
        'SOMATIC_VCF="${SOMATIC_VCF:-/mnt/zjl-bgi-zzb/peixunban/gl/data/chenxiaoliang_data/dsrct_data/dsrct/sunbinbin/somatic-vcf/sunbinbin_tumor.somatic.pass.vcf.gz}"',
        'SOMATIC_VCF="${SOMATIC_VCF:-}"',
    ),
    (
        'BAM="${BAM:-${NORMAL_BAM:-/mnt/zjl-bgi-zzb/peixunban/gl/data/chenxiaoliang_data/dsrct_data/dsrct/sunbinbin/wgs/sunbinbin_blood.align.bam}}"',
        'BAM="${BAM:-${NORMAL_BAM:?export NORMAL_BAM}}"',
    ),
]

ZJL_VCF_FALLBACK = re.compile(
    r'if \[\[ ! -s "\$\{IN_VCF\}" \]\]; then\s*\n'
    r'\s*IN_VCF="/mnt/zjl-bgi-zzb/peixunban/gl/data/chenxiaoliang_data/dsrct_data/dsrct/sunbinbin/somatic-vcf/\$\{PATIENT_ID\}_tumor\.somatic\.pass\.vcf\.gz"\s*\n'
    r'fi\s*\n',
    re.M,
)

ORCH_SUNBINBIN_CALLS = [
    ("run_cnv_all_sunbinbin.sh", "run_cnv_all.sh"),
    ("run_hla_all_sunbinbin.sh", "run_hla_all.sh"),
    ("run_dna_downstream_parallel_sunbinbin.sh", "run_dna_downstream_parallel.sh"),
    ("run_dna_all_sunbinbin.sh", "run_dna_all.sh"),
    ("build_hla_consensus_sunbinbin.sh", "build_hla_consensus.sh"),
]


def patch_text(text: str, *, dna: bool = True) -> tuple[str, dict[str, int]]:
    stats = {"hardcode": 0, "case_root": 0, "short_rna_root": 0, "bam_defaults": 0, "vcf_fallback": 0, "orch_calls": 0}
    t, n = HARDCODE_BLOCK.subn(PORTABLE_SNIPPET, text)
    stats["hardcode"] = n
    t, n = CASE_ROOT_RE.subn('CASE_ROOT="${CASE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"', t)
    stats["case_root"] = n
    t, n = SHORT_RNA_ROOT_RE.subn(
        'SHORT_RNA_ROOT="${SHORT_RNA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"', t
    )
    stats["short_rna_root"] = n
    t = t.replace(
        'NEOAG_ROOT="${NEOAG_ROOT:-/home/na/project/neoantigen/neoag_event_pipeline_v03_rc}"',
        'NEOAG_ROOT="${NEOAG_ROOT:-}"  # resolved by lib_portable_env.sh or inputs.env.sh',
    )
    if dna:
        for old, new in SUNBINBIN_BAM_DEFAULTS:
            if old in t:
                t = t.replace(old, new)
                stats["bam_defaults"] += 1
        for old, new in ORCH_SUNBINBIN_CALLS:
            if old in t:
                t = t.replace(old, new)
                stats["orch_calls"] += t.count(new) - text.count(new) if False else t.count(new)
                t = t.replace(old, new)
                stats["orch_calls"] += 1
    t2, n = ZJL_VCF_FALLBACK.subn(
        'if [[ ! -s "${IN_VCF}" && -n "${SOMATIC_VCF:-}" ]]; then\n  IN_VCF="${SOMATIC_VCF}"\nfi\n',
        t,
    )
    stats["vcf_fallback"] = 1 if n else 0
    t = t2
    return t, stats


def write_executable(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def sync_dna_templates() -> list[str]:
    dst = SHARED / "case_templates"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PORTABLE_ENV, dst / "lib_portable_env.sh")
    for name in ("lib_tool_timing.sh", "lib_site_defaults.sh"):
        shutil.copy2(SUN_DNA / name, dst / name)
    synced = []
    for src in sorted(SUN_DNA.glob("*.sh")):
        if src.name.startswith("lib_"):
            continue
        raw = src.read_text(encoding="utf-8", errors="replace")
        new, _ = patch_text(raw, dna=True)
        write_executable(dst / src.name, new)
        if src.name.endswith("_sunbinbin.sh"):
            generic = dst / src.name.replace("_sunbinbin.sh", ".sh")
            write_executable(generic, new)
        synced.append(src.name)
    return synced


def sync_rna_templates() -> list[str]:
    dst = SHARED / "short_rna_templates"
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(PORTABLE_ENV, dst / "lib_portable_env.sh")
    if (SUN_RNA / "lib_tool_timing.sh").is_file():
        shutil.copy2(SUN_RNA / "lib_tool_timing.sh", dst / "lib_tool_timing.sh")
    synced = []
    for src in sorted(SUN_RNA.glob("*.sh")):
        if src.name.startswith("lib_"):
            continue
        raw = src.read_text(encoding="utf-8", errors="replace")
        new, _ = patch_text(raw, dna=False)
        write_executable(dst / src.name, new)
        if src.name.endswith("_sunbinbin.sh"):
            generic = dst / src.name.replace("_sunbinbin.sh", ".sh")
            write_executable(generic, new)
        synced.append(src.name)
    # inputs template
    inp = (ROOT / "sunbinbin/short-rna/inputs.env.sh").read_text(encoding="utf-8", errors="replace")
    inp = inp.replace(
        'export NEOAG_ROOT="${NEOAG_ROOT:-/root/neo/src/na0707_upload_release}"',
        'export NEOAG_ROOT="${NEOAG_ROOT:-}"  # set by bootstrap_case.sh on each host',
    )
    inp = inp.replace(
        'export NEOAG_CONDA_BASE="${NEOAG_CONDA_BASE:-/root/neo/envs/miniforge3}"',
        'export NEOAG_CONDA_BASE="${NEOAG_CONDA_BASE:-}"',
    )
    inp = inp.replace(
        'export NEOAG_TOOLS_ROOT="${NEOAG_TOOLS_ROOT:-/root/neo/envs}"',
        'export NEOAG_TOOLS_ROOT="${NEOAG_TOOLS_ROOT:-}"',
    )
    inp = inp.replace('export PATIENT_ID="${PATIENT_ID:-sunbinbin}"', 'export PATIENT_ID="${PATIENT_ID:?set PATIENT_ID}"')
    (dst / "inputs.env.sh.template").write_text(inp, encoding="utf-8")
    synced.append("inputs.env.sh.template")
    readme = """# short_rna_templates

Per-tool RNA wrappers from sunbinbin gold path. Copy to `$CASE/short-rna/scripts/`:

```bash
CASE=/mnt/zzbnew/.../neoag/MYSAMPLE
mkdir -p "$CASE/short-rna/scripts"
rsync -a /mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts/short_rna_templates/ "$CASE/short-rna/scripts/"
cp .../inputs.env.sh.template "$CASE/short-rna/inputs.env.sh"
# edit PATIENT_ID, RNA_FASTQ*, export SOMATIC_VCF / HLA_CONSENSUS paths
```

Master orchestrator: `../rna/run_short_rna_master.sh` (run skill built-in) or `run_short_rna_all.sh`.
"""
    (dst / "README.md").write_text(readme, encoding="utf-8")
    return synced


def sync_sequenza() -> list[str]:
    dst = SHARED / "sequenza"
    dst.mkdir(parents=True, exist_ok=True)
    synced = []
    for src in [SUN_DNA / "run_sequenza_steps.sh", SKILL_SEQ / "run_sequenza_steps.sh"]:
        if src.is_file():
            raw = src.read_text(encoding="utf-8", errors="replace")
            write_executable(dst / "run_sequenza_steps.sh", raw)
            synced.append("run_sequenza_steps.sh")
            break
    for name in ("bam2seqz_nulsafe.py", "run_sequenza_fit.R"):
        for src in [SUN_DNA / name, SKILL_SEQ / name, DEPS / "tools/sequenza" / name]:
            if src.is_file():
                shutil.copy2(src, dst / name)
                if name.endswith(".py") or name.endswith(".sh"):
                    dst.joinpath(name).chmod(0o755)
                synced.append(name)
                break
    deps_seq = DEPS / "tools/sequenza"
    deps_seq.mkdir(parents=True, exist_ok=True)
    for name in synced:
        if (dst / name).is_file():
            shutil.copy2(dst / name, deps_seq / name)
    return synced


def sync_rna_master() -> list[str]:
    dst = SHARED / "rna"
    dst.mkdir(parents=True, exist_ok=True)
    synced = []
    for name in ("run_short_rna_master.sh", "harvest_easyfuse_artifacts.sh"):
        src = SKILL_RNA / name
        if src.is_file():
            shutil.copy2(src, dst / name)
            dst.joinpath(name).chmod(0o755)
            synced.append(name)
    return synced


def sync_snaf_splicemutr() -> list[str]:
    synced = []
    dst = SHARED / "snaf"
    dst.mkdir(parents=True, exist_ok=True)
    # Prefer existing NAS snaf workflow; refresh pipeline from skill if newer.
    allow = {"run_snaf_pipeline.sh", "snaf_sample_workflow.py"}
    skill_pipe = _SKILL_ROOT / "run_snaf_pipeline.sh"
    if skill_pipe.is_file():
        shutil.copy2(skill_pipe, dst / "run_snaf_pipeline.sh")
        synced.append("snaf/run_snaf_pipeline.sh")
    for name in sorted(allow):
        if name == "run_snaf_pipeline.sh":
            continue
        for src in [dst / name, ROOT / "shared_scripts/snaf" / name]:
            if src.is_file():
                synced.append(f"snaf/{name}")
                break
    return synced


def patch_sunbinbin_in_place() -> None:
    """Keep sunbinbin/scripts aligned with templates (optional convenience)."""
    shutil.copy2(PORTABLE_ENV, SUN_DNA / "lib_portable_env.sh")
    for src in sorted(SUN_DNA.glob("*.sh")):
        if src.name.startswith("lib_"):
            continue
        raw = src.read_text(encoding="utf-8", errors="replace")
        new, st = patch_text(raw, dna=True)
        if new != raw:
            bak = src.with_suffix(src.suffix + ".bak_pre_portable")
            if not bak.exists():
                shutil.copy2(src, bak)
            write_executable(src, new)
            print(f"  patched sunbinbin/{src.name} {st}")


def main() -> None:
    if not PORTABLE_ENV.is_file():
        raise SystemExit(f"missing portable_env: {PORTABLE_ENV}")
    pe_dst = DEPS / "tools/run/lib/portable_env.sh"
    pe_dst.parent.mkdir(parents=True, exist_ok=True)
    if PORTABLE_ENV.resolve() != pe_dst.resolve():
        shutil.copy2(PORTABLE_ENV, pe_dst)

    print("=== DNA case_templates ===")
    dna = sync_dna_templates()
    print(f"  {len(dna)} scripts")

    print("=== short_rna_templates ===")
    rna = sync_rna_templates()
    print(f"  {len(rna)} items")

    print("=== sequenza ===")
    seq = sync_sequenza()
    print(f"  {seq}")

    print("=== rna master ===")
    rm = sync_rna_master()
    print(f"  {rm}")

    print("=== snaf refresh ===")
    sn = sync_snaf_splicemutr()
    print(f"  {sn or ['unchanged']}")

    print("=== patch sunbinbin/scripts in place ===")
    patch_sunbinbin_in_place()

    top_readme = SHARED / "README.md"
    top_readme.write_text(
        """# shared_scripts — 66 / 134 / 169 通用脚本

| 目录 | 用途 |
|------|------|
| `case_templates/` | DNA: HLA, CNV, LOHHLA, VEP, pVACseq, sliding |
| `short_rna_templates/` | RNA per-tool wrappers + `inputs.env.sh.template` |
| `sequenza/` | Sequenza pileup/fit (per-chrom bin + fread fit) |
| `rna/` | Built-in `run_short_rna_master.sh` |
| `snaf/` | SNAF pipeline |
| `splicemutr/` | SpliceMutr patient runner |

## 新病例

```bash
CASE=/mnt/zzbnew/.../neoag/MYSAMPLE
rsync -a .../shared_scripts/case_templates/ "$CASE/scripts/"
rsync -a .../shared_scripts/short_rna_templates/ "$CASE/short-rna/scripts/"
cp .../short_rna_templates/inputs.env.sh.template "$CASE/short-rna/inputs.env.sh"
export PATIENT_ID TUMOR_BAM NORMAL_BAM SOMATIC_VCF
bash "$CASE/scripts/run_hla_all.sh"
```

运行前 **必须** export 样本 BAM/VCF；脚本不再默认 sunbinbin 的 zjl 路径。
NEOAG_ROOT 由 `lib_portable_env.sh` / `bootstrap_case.sh` 按主机解析。

同步：`python3 sync_shared_scripts.py`（neoag-basic-tools-run/scripts/）
""",
        encoding="utf-8",
    )
    print("DONE")


if __name__ == "__main__":
    main()
