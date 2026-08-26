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
# SpecHLA prefix env (pack only if it exists on THIS host)
SPECHLA_GOLD="${SPECHLA_GOLD:-}"
if [[ -z "${SPECHLA_GOLD}" ]]; then
  _ips=" $(hostname -I 2>/dev/null || true) "
  if [[ "${_ips}" == *" 10.200.50.134 "* ]]; then
    SPECHLA_GOLD=/home/na/project/neoantigen/neoag_event_pipeline_v03_rc/tools/SpecHLA/spechla_env
  elif [[ "${_ips}" == *" 10.200.65.66 "* ]]; then
    SPECHLA_GOLD=/root/neo/envs/miniforge3/envs/spechla_env
  elif [[ "${_ips}" == *" 10.200.65.169 "* ]]; then
    SPECHLA_GOLD=/root/neo/env_tool/tools/SpecHLA/spechla_env
  fi
fi

IFS=',' read -r -a want <<<"${NAMES}"
if [[ -z "$NAMES" ]]; then
  want=("${default_names[@]}")
  [[ -d "${SPECHLA_GOLD}/bin" ]] && want+=("spechla_env")
fi

log "packing on $(hostname) conda=${CONDA_BASE} -> ${PACK_DIR}"
for name in "${want[@]}"; do
  [[ -n "$name" ]] || continue
  out="${PACK_DIR}/${name}.tar.gz"
  if [[ -s "$out" && "${FORCE:-0}" != "1" ]]; then
    ok "already packed: $out (FORCE=1 to rebuild)"
    continue
  fi
  if [[ -s "$out" && "${FORCE:-0}" == "1" ]]; then
    mv -f "$out" "${out}.bak_$(date +%Y%m%d_%H%M%S)"
    log "FORCE: moved stale pack aside for ${name}"
  fi
  tmp="/tmp/neoag_pack_${name}.tar.gz"
  rm -f "$tmp"
  if [[ "$name" == "spechla_env" ]]; then
    src="${SPECHLA_GOLD}"
    [[ -d "$src/bin" ]] || { warn "skip missing spechla_env gold ${src}"; continue; }
    log "conda-pack -p spechla_env <- ${src}"
    if "$PACK_BIN" -p "$src" -o "$tmp" --ignore-editable-packages --ignore-missing-files; then
      mv -f "$tmp" "$out"
      chmod a+rw "$out" || true
      ok "packed ${name} $(du -h "$out" | awk '{print $1}')"
    else
      rm -f "$tmp"
      warn "pack failed: ${name}"
    fi
    continue
  fi
  src="${CONDA_BASE}/envs/${name}"
  [[ -d "$src" ]] || { warn "skip missing ${name}"; continue; }
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
