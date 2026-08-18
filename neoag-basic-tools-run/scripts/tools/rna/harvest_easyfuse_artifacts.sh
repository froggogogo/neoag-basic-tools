#!/usr/bin/env bash
# Best-effort: link STAR BAM / Arriba / STAR-Fusion outputs from EasyFuse work dirs
# so regtools / pVACfuse / evidence can reuse them without standalone caller runs.
set -euo pipefail

SHORT_RNA_ROOT="${SHORT_RNA_ROOT:?SHORT_RNA_ROOT required}"
PATIENT_ID="${PATIENT_ID:-${SAMPLE_ID:-sample}}"
FORCE="${FORCE:-0}"

STAR_DIR="${SHORT_RNA_ROOT}/star"
ARRIBA_DIR="${SHORT_RNA_ROOT}/arriba"
SF_DIR="${SHORT_RNA_ROOT}/star-fusion"
STAR_BAM="${STAR_DIR}/Aligned.sortedByCoord.out.bam"
ARRIBA_TSV="${ARRIBA_DIR}/${PATIENT_ID}.fusions.tsv"
SF_TSV="${SF_DIR}/star-fusion.fusion_predictions.tsv"

mkdir -p "${STAR_DIR}" "${ARRIBA_DIR}" "${SF_DIR}"

search_roots() {
  local r
  for r in \
    "${SHORT_RNA_ROOT}/easyfuse" \
    "${NEOAG_EASYFUSE_HOME:-}/work" \
    "${NXF_WORK:-}" \
    "${NEOAG_ROOT:-}/work"
  do
    [[ -n "$r" && -d "$r" ]] && printf '%s\n' "$r"
  done
}

link_or_copy() {
  local src="$1" dst="$2"
  [[ -s "$src" ]] || return 1
  if [[ "$src" -ef "$dst" ]]; then
    return 0
  fi
  if [[ -e "$dst" && "$FORCE" != "1" ]]; then
    return 0
  fi
  rm -f "$dst"
  ln -sf "$src" "$dst" 2>/dev/null || cp -f "$src" "$dst"
  echo "  OK  $(basename "$dst") <- ${src}"
  return 0
}

find_newest() {
  local pattern="$1"
  local root found=""
  while IFS= read -r root; do
    while IFS= read -r f; do
      [[ -s "$f" ]] || continue
      if [[ -z "$found" || "$f" -nt "$found" ]]; then
        found="$f"
      fi
    done < <(find "$root" -type f -name "$pattern" 2>/dev/null || true)
  done < <(search_roots)
  [[ -n "$found" ]] && printf '%s' "$found"
}

echo "==> harvest_easyfuse_artifacts $(date -Is) patient=${PATIENT_ID}"

if [[ ! -s "$STAR_BAM" || "$FORCE" == "1" ]]; then
  bam="$(find_newest 'Aligned.sortedByCoord.out.bam' || true)"
  if [[ -n "$bam" ]]; then
    link_or_copy "$bam" "$STAR_BAM"
    bai="${bam}.bai"
    [[ -s "$bai" ]] && link_or_copy "$bai" "${STAR_BAM}.bai" || true
    date -Is > "${STAR_DIR}/.star.done"
  else
    echo "  MISS STAR BAM (regtools may skip)"
  fi
else
  echo "  SKIP STAR BAM (exists)"
fi

if [[ ! -s "$ARRIBA_TSV" || "$FORCE" == "1" ]]; then
  arriba="$(find_newest '*.fusions.tsv' || true)"
  if [[ -n "$arriba" ]]; then
    link_or_copy "$arriba" "$ARRIBA_TSV"
    date -Is > "${ARRIBA_DIR}/.arriba.done"
  else
    echo "  MISS Arriba fusions (pVACfuse may skip)"
  fi
else
  echo "  SKIP Arriba (exists)"
fi

if [[ ! -s "$SF_TSV" || "$FORCE" == "1" ]]; then
  sf="$(find_newest 'star-fusion.fusion_predictions.tsv' || true)"
  if [[ -z "$sf" ]]; then
    sf="$(find_newest '*fusion_predictions.tsv' || true)"
  fi
  if [[ -n "$sf" ]]; then
    link_or_copy "$sf" "$SF_TSV"
    date -Is > "${SF_DIR}/.star_fusion.done"
  else
    echo "  MISS STAR-Fusion table (optional)"
  fi
else
  echo "  SKIP STAR-Fusion (exists)"
fi

echo "==> harvest_easyfuse_artifacts done"
