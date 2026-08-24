# Portable overlay (134/66/169). Keep sample defaults below.
if [[ -f /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/bootstrap_case.sh ]]; then
  # shellcheck disable=SC1091
  source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/bootstrap_case.sh
fi
unset TF_USE_LEGACY_KERAS KERAS_BACKEND || true

#!/usr/bin/env bash
# =============================================================================
# Site defaults shared by sunbinbin CNV || HLA orchestrators
#
# Fixes that blocked prior runs:
#   1) tools.env.sh sets NEOAG_REFERENCE_FASTA under neoag_event_pipeline_v03_rc
#      which often does NOT exist on disk. Prefer real NAS hg38 FASTA paths.
#   2) HLA-LA PRG graph sequences.txt (and some translation/*) may be mode 750
#      owned by another uid -> Assertion `sequencesStream.is_open()' failed.
#      Try docker-root chmod (host user in docker group) when unreadable.
#
# Usage (after source conf/tools.env.sh):
#   # shellcheck source=/dev/null
#   source "${SCRIPT_DIR}/lib_site_defaults.sh"
#   resolve_ref_fasta
#   ensure_hlala_graph_readable   # only if HLA-LA will run
# =============================================================================

# Candidate reference genomes: neoag-100T only (never zjl).
_DEFAULT_REF_CANDIDATES=(
  "${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/refs/sequenza/reference/GRCh38.primary_assembly.chr.fa"
  "${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/refs/hg38/Homo_sapiens_assembly38.fasta"
)

_DEFAULT_HLALA_GRAPH="${HLA_LA_GRAPH:-${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/refs/hla/PRG_MHC_GRCh38_withIMGT}"
_DEFAULT_HLALA_CONDA="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}/tools/neodata_tools/HLA-LA/.conda"
_DEFAULT_HLALA_HOME="${_DEFAULT_HLALA_CONDA}/opt/hla-la"
_DEFAULT_HLALA_BIN="${_DEFAULT_HLALA_CONDA}/bin/HLA-LA.pl"

# Return 0 if FASTA.fai first contig looks like "chr*" (GATK-style).
_ref_fai_has_chr_prefix() {
  local fa="$1"
  local fai="${fa}.fai"
  [[ -s "${fai}" ]] || fai="$(readlink -f "${fa}" 2>/dev/null).fai"
  [[ -s "${fai}" ]] || return 1
  local first
  first="$(head -n 1 "${fai}" | cut -f1)"
  [[ "${first}" == chr* ]]
}

# Pick a readable FASTA; always re-export so child steps see the same path.
# Prefer assemblies whose .fai contigs are chr* — BAM and sequenza CHROMS use chr naming.
resolve_ref_fasta() {
  local pick=""
  local c prefer_chr="${REF_PREFER_CHR:-1}"

  _try_pick() {
    local cand="$1"
    [[ -s "${cand}" ]] || return 1
    if [[ "${prefer_chr}" == "1" ]] && ! _ref_fai_has_chr_prefix "${cand}"; then
      echo "WARN: skip FASTA (no chr* contigs in .fai): ${cand}" >&2
      return 1
    fi
    pick="${cand}"
    return 0
  }

  # Honor explicit REF_FASTA only if usable; warn if contig style mismatches preference.
  if [[ -n "${REF_FASTA:-}" && -s "${REF_FASTA}" ]]; then
    if [[ "${prefer_chr}" == "1" ]] && ! _ref_fai_has_chr_prefix "${REF_FASTA}"; then
      echo "WARN: REF_FASTA has no chr* contigs (BAM/sequenza expect chr): ${REF_FASTA}" >&2
      echo "      searching defaults for a chr-style genome..." >&2
    else
      pick="${REF_FASTA}"
    fi
  fi

  if [[ -z "${pick}" && -n "${NEOAG_REFERENCE_FASTA:-}" && -s "${NEOAG_REFERENCE_FASTA}" ]]; then
    if [[ "${prefer_chr}" == "1" ]] && ! _ref_fai_has_chr_prefix "${NEOAG_REFERENCE_FASTA}"; then
      echo "WARN: NEOAG_REFERENCE_FASTA has no chr* contigs: ${NEOAG_REFERENCE_FASTA}" >&2
    else
      pick="${NEOAG_REFERENCE_FASTA}"
    fi
  elif [[ -n "${NEOAG_REFERENCE_FASTA:-}" && ! -s "${NEOAG_REFERENCE_FASTA:-}" ]]; then
    echo "WARN: NEOAG_REFERENCE_FASTA missing/unreadable: ${NEOAG_REFERENCE_FASTA}" >&2
    echo "      (tools.env.sh often points into the source tree; using NAS/quarantine fallbacks)" >&2
  fi

  if [[ -z "${pick}" ]]; then
    for c in "${_DEFAULT_REF_CANDIDATES[@]}"; do
      if _try_pick "${c}"; then
        break
      fi
    done
  fi

  # Last resort: any non-empty candidate (even no-chr), for tools that allow remap.
  if [[ -z "${pick}" ]]; then
    for c in "${_DEFAULT_REF_CANDIDATES[@]}"; do
      if [[ -s "${c}" ]]; then
        pick="${c}"
        echo "WARN: using non-chr FASTA as last resort: ${pick}" >&2
        break
      fi
    done
  fi

  if [[ -z "${pick}" ]]; then
    echo "ERROR: no usable hg38 FASTA found. Set REF_FASTA=/path/to/genome.fa (prefer chr* contigs)" >&2
    return 1
  fi

  export REF_FASTA="${pick}"
  export NEOAG_REFERENCE_FASTA="${pick}"
  if _ref_fai_has_chr_prefix "${REF_FASTA}"; then
    echo "[lib_site_defaults] REF_FASTA=${REF_FASTA} (chr* contigs OK)"
  else
    echo "[lib_site_defaults] REF_FASTA=${REF_FASTA} (WARNING: no chr* contigs)"
  fi
}

# Export HLA-LA tool paths with site defaults (overrideable).
resolve_hlala_paths() {
  export HLALA_HOME="${HLALA_HOME:-${HLA_LA_HOME:-${_DEFAULT_HLALA_HOME}}}"
  export HLALA_BIN="${HLALA_BIN:-${HLA_LA_BIN:-${_DEFAULT_HLALA_BIN}}}"
  export HLALA_GRAPH="${HLALA_GRAPH:-${HLA_LA_GRAPH:-${_DEFAULT_HLALA_GRAPH}}}"
  export HLA_LA_HOME="${HLALA_HOME}"
  export HLA_LA_BIN="${HLALA_BIN}"
  export HLA_LA_GRAPH="${HLALA_GRAPH}"
  export HLALA_CONDA_BIN="${HLALA_CONDA_BIN:-${_DEFAULT_HLALA_CONDA}/bin}"
}

# Ensure PRG graph files needed by HLA-LA binary are world-readable.
# Prefer docker root chmod when host user cannot chmod NAS files (common case).
ensure_hlala_graph_readable() {
  resolve_hlala_paths
  local graph="${HLALA_GRAPH}"
  local seq="${graph}/sequences.txt"
  local need_fix=0
  local f

  if [[ ! -d "${graph}" ]]; then
    echo "ERROR: HLA-LA graph dir missing: ${graph}" >&2
    return 1
  fi

  if [[ ! -e "${seq}" ]]; then
    echo "ERROR: missing ${seq} (HLA-LA needs sequences.txt in graph dir)" >&2
    return 1
  fi

  if [[ ! -r "${seq}" ]]; then
    echo "WARN: sequences.txt not readable by $(id -un): ${seq}" >&2
    need_fix=1
  fi

  # Spot-check a few critical readable paths
  for f in "${graph}/serializedGRAPH" "${graph}/extendedReferenceGenome/extendedReferenceGenome.fa"; do
    if [[ -e "${f}" && ! -r "${f}" ]]; then
      echo "WARN: not readable: ${f}" >&2
      need_fix=1
    fi
  done

  if [[ "${need_fix}" -eq 0 ]]; then
    # Also scan shallow unreadable modes that bite later stages
    if find "${graph}" -maxdepth 2 \( -type f -o -type d \) ! -readable 2>/dev/null | head -1 | grep -q .; then
      need_fix=1
    fi
  fi

  if [[ "${need_fix}" -eq 0 ]]; then
    echo "[lib_site_defaults] HLA-LA graph readable: ${graph}"
    return 0
  fi

  echo "[lib_site_defaults] Attempting to fix HLA-LA graph permissions via docker root..."
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: graph not readable and docker not available to chmod." >&2
    echo "  Fix manually (as root): chmod -R a+rX ${graph}" >&2
    return 1
  fi

  # alpine is small; reuse if present. Fall back to busybox if pull fails.
  local img="${HLALA_CHMOD_IMAGE:-alpine:3.19}"
  if ! docker run --rm -v "${graph}:/graph" "${img}" \
      sh -c 'chmod -R a+rX /graph 2>/dev/null; test -r /graph/sequences.txt' ; then
    echo "ERROR: docker chmod of ${graph} failed." >&2
    echo "  Fix manually (as root): chmod -R a+rX ${graph}" >&2
    return 1
  fi

  if [[ ! -r "${seq}" ]]; then
    echo "ERROR: sequences.txt still unreadable after docker chmod: ${seq}" >&2
    return 1
  fi
  echo "[lib_site_defaults] HLA-LA graph permissions fixed: ${seq}"
}
