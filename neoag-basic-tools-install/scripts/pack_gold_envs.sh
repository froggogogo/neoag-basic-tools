#!/usr/bin/env bash
# Pack gold conda envs on THIS host into $DEPS_DIR/packages/conda_packs/
# so other 134/66/169 hosts can unpack via ensure_host_runtime.sh.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/conda.sh"

DEPS_DIR="${DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
PACK_DIR="${PACK_DIR:-${DEPS_DIR}/packages/conda_packs}"
export ALLOW_ROOT_CONDA=1
NAMES="${1:-}"

discover_conda || die "NO_CONDA" "need host conda to pack"
ensure_dir "$PACK_DIR" 777

if ! command -v conda-pack >/dev/null 2>&1 && [[ ! -x "${CONDA_BASE}/bin/conda-pack" ]]; then
  log "installing conda-pack"
  conda_frontend install -y -n base -c conda-forge conda-pack || \
    "${CONDA_BASE}/bin/python" -m pip install conda-pack
fi
PACK_BIN="${CONDA_BASE}/bin/conda-pack"
[[ -x "$PACK_BIN" ]] || PACK_BIN="$(command -v conda-pack)"

default_names=()
for n in neoag-snaf neoag-splice neoag-splicemutr neoag-salmon-cpp neoag-fusion \
         neoag-optitype neoag-pvactools711 neoag-samtools19; do
  [[ -d "${CONDA_BASE}/envs/${n}" ]] && default_names+=("$n")
done

IFS=',' read -r -a want <<<"${NAMES}"
if [[ -z "$NAMES" ]]; then
  want=("${default_names[@]}")
fi

log "packing on $(hostname) conda=${CONDA_BASE} -> ${PACK_DIR}"
for name in "${want[@]}"; do
  [[ -n "$name" ]] || continue
  src="${CONDA_BASE}/envs/${name}"
  [[ -d "$src" ]] || { warn "skip missing ${name}"; continue; }
  out="${PACK_DIR}/${name}.tar.gz"
  if [[ -s "$out" ]]; then
    ok "already packed: $out"
    continue
  fi
  tmp="/tmp/neoag_pack_${name}.tar.gz"
  rm -f "$tmp"
  log "conda-pack ${name} (may take a while)"
  if "$PACK_BIN" -n "$name" -o "$tmp" --ignore-editable-packages --ignore-missing-files; then
    mv -f "$tmp" "$out"
    chmod a+rw "$out" || true
    ok "packed ${name} $(du -h "$out" | awk '{print $1}')"
  else
    rm -f "$tmp"
    warn "pack failed: ${name}"
  fi
done
ok "pack_gold_envs done"
