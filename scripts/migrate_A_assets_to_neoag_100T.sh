#!/usr/bin/env bash
# Materialize neoag-basic-tools-install A-class assets onto neoag_100T.
# World-writable (a+rwx) for cross-host shared use.
#
# src/neo: ONLY the install-skill slice (yml + install_*.sh + sequenza fit R),
# not the full neo git tree. Skill remains independent of neo repository.
set -euo pipefail
umask 000

DST_ROOT="${DST_ROOT:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
SRC_ROOT="${SRC_ROOT:-/mnt/zjl-bgi-zzb/peixunban/gl/liup/neodata4git}"
NEO_SRC="${NEO_SRC:-/mnt/zzbnew/peixunban/gl/mjx/neogit/neo}"
LOGDIR="${LOGDIR:-/mnt/neoag_100T/majiaxin/logs}"
STAMP="$(date +%Y%m%d_%H%M%S)"
MAINLOG="${LOGDIR}/migrate_A_assets_${STAMP}.nohup.out"
STATUS="${LOGDIR}/migrate_A_assets.status"
DONE="${LOGDIR}/migrate_A_assets.done"
FAIL="${LOGDIR}/migrate_A_assets.fail"
PIDFILE="${LOGDIR}/migrate_A_assets.pid"
MANIFEST="${DST_ROOT}/manifests/migrate_A_assets.tsv"

mkdir -p "$DST_ROOT" "$LOGDIR" "$(dirname "$DST_ROOT")"
chmod 777 "$(dirname "$DST_ROOT")" "$DST_ROOT" "$LOGDIR" 2>/dev/null || true

# Re-exec with tee if not already logging to MAINLOG
if [[ "${MIGRATE_A_LOGGING:-0}" != "1" ]]; then
  export MIGRATE_A_LOGGING=1
  exec > >(tee -a "$MAINLOG") 2>&1
fi

echo "[$(date -Is)] START migrate A assets host=$(hostname) pid=$$"
echo "SRC=$SRC_ROOT"
echo "DST=$DST_ROOT"
echo "running" > "$STATUS"
echo "$$" > "$PIDFILE"
rm -f "$DONE" "$FAIL"

MAP=(
  "data/ref/hg38|refs/hg38"
  "data/ref/ctat|refs/ctat"
  "data/rna|refs/rna"
  "data/hla|refs/hla"
  "data/vep|refs/vep"
  "data/easyfuse|refs/easyfuse"
  "data/facets|refs/facets"
  "data/hmf|refs/hmf"
  "data/lohhla|refs/lohhla"
  "data/ascat|refs/ascat"
  "data/sequenza|refs/sequenza"
  "data/snaf|refs/snaf"
  "data/normal|refs/normal"
  "data/sample_identity|refs/sample_identity"
  "data/predictors|licenses/predictors"
  "tools|tools/neodata_tools"
  "work/vep_plugins|work/vep_plugins"
)

# Install-skill slice only (not full neo tree).
NEO_SLICE_FILES=(
  conda/env.neoag-tools.yml
  conda/env.neoag-fusion.yml
  conda/env.neoag-splice.yml
  conda/env.neoag-splicemutr.yml
  conda/env.neoag-sequenza.yml
  conda/env.neoag-vep.yml
  conda/env.neoag-gatk.yml
  scripts/install_optitype.sh
  scripts/install_facets.sh
  scripts/install_fusion_tools.sh
  scripts/install_lohhla.sh
  scripts/install_splice_tools.sh
  scripts/install_splicemutr.sh
  scripts/install_vep.sh
  scripts/install_gatk.sh
  scripts/run_sequenza_fit.R
)

mkdir -p \
  "$DST_ROOT/refs" \
  "$DST_ROOT/licenses" \
  "$DST_ROOT/packages/installers" \
  "$DST_ROOT/packages/conda_pkgs" \
  "$DST_ROOT/packages/pip_cache" \
  "$DST_ROOT/tools" \
  "$DST_ROOT/software" \
  "$DST_ROOT/configs" \
  "$DST_ROOT/src" \
  "$DST_ROOT/manifests" \
  "$DST_ROOT/logs" \
  "$DST_ROOT/work" \
  "$DST_ROOT/installer"
chmod -R a+rwx "$DST_ROOT" || true

if [[ ! -f "$MANIFEST" ]]; then
  printf 'item\tstatus\tsize_or_detail\n' > "$MANIFEST"
fi

already_ok() {
  local label="$1"
  [[ -f "$MANIFEST" ]] || return 1
  awk -F'\t' -v l="$label" '$1==l && $2=="OK" {found=1} END{exit !found}' "$MANIFEST"
}

mark_row() {
  local label="$1" status="$2" detail="$3"
  if grep -q "^${label}	" "$MANIFEST" 2>/dev/null; then
    # rewrite that line
    local tmp
    tmp="$(mktemp)"
    awk -F'\t' -v l="$label" -v s="$status" -v d="$detail" '
      BEGIN{OFS="\t"}
      $1==l {$2=s; $3=d; updated=1}
      {print}
      END{if(!updated) print l,s,d}
    ' "$MANIFEST" > "$tmp"
    mv "$tmp" "$MANIFEST"
  else
    echo -e "${label}\t${status}\t${detail}" >> "$MANIFEST"
  fi
  chmod a+rw "$MANIFEST" 2>/dev/null || true
}

rsync_one() {
  local src="$1" dst="$2" label="$3"
  echo "[$(date -Is)] === ${label} ==="
  echo "  ${src} -> ${dst}"
  if already_ok "$label"; then
    echo "  SKIP already OK in manifest"
    return 0
  fi
  if [[ ! -e "$src" ]]; then
    echo "  SKIP missing source"
    mark_row "$label" "MISSING_SRC" "$src"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" && ! -L "$src" ]]; then
    rsync -a --info=stats2 --chmod=a+rwx "${src}/" "${dst}/"
  elif [[ -L "$src" ]]; then
    rsync -aL --info=stats2 --chmod=a+rwx "${src}/" "${dst}/"
  else
    rsync -a --chmod=a+rwx "$src" "$dst"
  fi
  chmod -R a+rwx "$dst" 2>/dev/null || true
  local sz
  sz="$(du -sh "$dst" 2>/dev/null | awk '{print $1}')" || sz="?"
  echo "  DONE size=${sz}"
  mark_row "$label" "OK" "$sz"
}

seed_neo_install_slice() {
  local neo_dst="${DST_ROOT}/src/neo"
  echo "[$(date -Is)] === src/neo (install-skill slice only) ==="
  if already_ok "src/neo"; then
    echo "  SKIP already OK in manifest"
    return 0
  fi
  if [[ ! -d "$NEO_SRC" ]]; then
    echo "  WARN neo src missing: $NEO_SRC"
    mark_row "src/neo" "MISSING_SRC" "$NEO_SRC"
    return 0
  fi

  # Drop accidental full-tree copy from older migrator versions.
  if [[ -d "$neo_dst" ]]; then
    echo "  clearing previous src/neo before slice seed"
    rm -rf "$neo_dst"
  fi
  mkdir -p "$neo_dst/conda" "$neo_dst/scripts" "$neo_dst/conf" "$neo_dst/bin"

  local f missing=0
  for f in "${NEO_SLICE_FILES[@]}"; do
    if [[ -f "${NEO_SRC}/${f}" ]]; then
      rsync -a --chmod=a+rwx "${NEO_SRC}/${f}" "${neo_dst}/${f}"
      echo "  + ${f}"
    else
      echo "  MISSING ${f}"
      missing=$((missing + 1))
    fi
  done

  # install_*.sh may append to conf/tools.env.sh; seed a stub if absent.
  if [[ -f "${NEO_SRC}/conf/tools.env.sh" ]]; then
    rsync -a --chmod=a+rwx "${NEO_SRC}/conf/tools.env.sh" "${neo_dst}/conf/tools.env.sh"
    echo "  + conf/tools.env.sh"
  elif [[ ! -f "${neo_dst}/conf/tools.env.sh" ]]; then
    cat > "${neo_dst}/conf/tools.env.sh" <<'EOF'
#!/usr/bin/env bash
# Stub for neoag-basic-tools-install slice (install_*.sh may append here).
EOF
    chmod a+rwx "${neo_dst}/conf/tools.env.sh"
    echo "  + conf/tools.env.sh (stub)"
  fi

  chmod -R a+rwx "$neo_dst" 2>/dev/null || true
  local sz
  sz="$(du -sh "$neo_dst" 2>/dev/null | awk '{print $1}')" || sz="?"
  if [[ "$missing" -gt 0 ]]; then
    echo "  DONE with ${missing} missing file(s) size=${sz}"
    mark_row "src/neo" "PARTIAL" "missing=${missing};${sz}"
  else
    echo "  DONE size=${sz}"
    mark_row "src/neo" "OK" "$sz"
  fi
}

on_err() {
  echo "[$(date -Is)] FAILED"
  echo "failed" > "$STATUS"
  date -Is > "$FAIL"
}
trap on_err ERR

for entry in "${MAP[@]}"; do
  src_rel="${entry%%|*}"
  dst_rel="${entry##*|}"
  rsync_one "${SRC_ROOT}/${src_rel}" "${DST_ROOT}/${dst_rel}" "${dst_rel}"
done

seed_neo_install_slice

cat > "${DST_ROOT}/README.md" <<'EOF'
# neoag-basic-tools-install-deps

Materialized A-class assets for neoag-basic-tools-install
(copied from zjl neodata4git).

src/neo holds only the **install-skill slice** (conda env yml + install_*.sh
+ run_sequenza_fit.R), not a full neo git checkout. The install skill does
not require cloning the neo repository.

Default --deps-dir for the skill (neoag_100T).

Permissions: world a+rwx for cross-host shared use.
EOF
chmod a+rwx "${DST_ROOT}/README.md" || true

echo "[$(date -Is)] final chmod -R a+rwx (may take long on huge trees)"
chmod -R a+rwx "$DST_ROOT" || true

echo "[$(date -Is)] DONE"
date -Is > "$DONE"
echo "done" > "$STATUS"
du -sh "$DST_ROOT" || true
cat "$MANIFEST" || true
