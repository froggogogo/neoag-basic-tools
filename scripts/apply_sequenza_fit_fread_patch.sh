#!/usr/bin/env bash
# Apply fread-hardened Sequenza fit script onto a neo tree copy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_SRC="${SCRIPT_DIR}/patches/run_sequenza_fit.fread.R"
FIT_R=""
BACKUP=1

usage() {
  cat <<'EOF'
Usage:
  bash scripts/apply_sequenza_fit_fread_patch.sh --fit-r /path/to/run_sequenza_fit.R

Options:
  --fit-r PATH   Target R script (required)
  --no-backup    Do not write .bak_<timestamp>
  -h, --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fit-r) FIT_R="${2:-}"; shift 2 ;;
    --no-backup) BACKUP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$FIT_R" ]] || { usage; exit 2; }
[[ -f "$PATCH_SRC" ]] || { echo "Missing patch template: $PATCH_SRC" >&2; exit 1; }
[[ -f "$FIT_R" ]] || { echo "Missing target: $FIT_R" >&2; exit 1; }

if [[ "$BACKUP" == "1" ]]; then
  cp -a "$FIT_R" "${FIT_R}.bak_$(date +%Y%m%d_%H%M%S)_pre_fread"
fi
cp -a "$PATCH_SRC" "$FIT_R"
chmod a+r "$FIT_R" 2>/dev/null || true
echo "[ok] applied fread Sequenza fit patch -> $FIT_R"
echo "     ensure neoag-sequenza has r-data.table (installer ensure_sequenza_datatable)"
