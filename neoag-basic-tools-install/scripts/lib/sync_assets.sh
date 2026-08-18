#!/usr/bin/env bash
# Sync assets from asset-source into DEPS_DIR (parameterized, no machine hardcode)

# Relative mappings: SRC_REL -> DEPS_REL
# Source root = ASSET_SOURCE (default neodata4git)
declare -a ASSET_MAP=(
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

# Probe that a path is readable by the installing user (not just -e).
asset_readable() {
  local p="$1"
  if [[ -L "$p" ]]; then
    [[ -e "$p" ]] || return 1
  fi
  if [[ -d "$p" ]]; then
    # directory: must be listable and have at least one readable child (or empty ok if listable)
    [[ -r "$p" && -x "$p" ]] || return 1
    # try reading one entry if present
    local sample
    sample="$(find "$p" -maxdepth 2 -type f 2>/dev/null | head -1 || true)"
    if [[ -n "$sample" ]]; then
      [[ -r "$sample" ]] || return 1
      # byte-level open check
      head -c 1 "$sample" >/dev/null 2>&1 || return 1
    fi
    return 0
  fi
  if [[ -f "$p" ]]; then
    [[ -r "$p" ]] || return 1
    head -c 1 "$p" >/dev/null 2>&1 || return 1
    return 0
  fi
  return 1
}

# True if path is a symlink whose ultimate target is outside DEPS_DIR.
is_external_symlink() {
  local p="$1"
  [[ -L "$p" ]] || return 1
  local target resolved deps
  target="$(readlink "$p" || true)"
  [[ -n "$target" ]] || return 0
  if [[ "$target" != /* ]]; then
    target="$(cd "$(dirname "$p")" && pwd -P)/${target}"
  fi
  if [[ -e "$target" ]]; then
    resolved="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target")"
  else
    resolved="$target"
  fi
  deps="$(cd "${DEPS_DIR}" 2>/dev/null && pwd -P || echo "${DEPS_DIR}")"
  [[ "$resolved" != "$deps" && "$resolved" != "$deps"/* ]]
}

materialize_or_remove_dst() {
  # Prepare dst for a fresh sync: remove empty dirs / replace external symlinks when copying.
  local dst="$1"
  local mode="$2"
  local force="${FORCE_RESYNC:-0}"

  if [[ -L "$dst" ]]; then
    if [[ "$mode" == "copy" || "$force" == "1" ]]; then
      warn "目标是软链，将拆除以便 ${mode}: $dst -> $(readlink "$dst" 2>/dev/null || echo '?')"
      rm -f "$dst"
      return 0
    fi
    # symlink mode: keep if already correct (handled by caller)
    return 0
  fi

  if [[ -d "$dst" && -z "$(find "$dst" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)" ]]; then
    rmdir "$dst" 2>/dev/null || true
  fi
}

sync_one() {
  local src="$1"
  local dst="$2"
  local mode="$3" # symlink|copy

  if [[ ! -e "$src" ]]; then
    warn "资产缺失，跳过: $src"
    echo -e "${dst}\t${src}\tMISSING\t-" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
    return 1
  fi

  if ! asset_readable "$src"; then
    warn "资产存在但当前用户不可读: $src"
    echo -e "${dst}\t${src}\tUNREADABLE_SRC\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
    if [[ "$mode" == "symlink" ]]; then
      err "reason=ASSET_UNREADABLE"
      err "源目录不可读，软链装上后运行机也无法用。请换可读账号、修权限，或改用 --sync-mode copy（仍需要安装期可读才能复制）。"
      return 1
    fi
    return 1
  fi

  ensure_dir "$(dirname "$dst")" 777
  materialize_or_remove_dst "$dst" "$mode"

  if [[ -e "$dst" || -L "$dst" ]]; then
    if [[ -L "$dst" ]]; then
      local cur
      cur="$(readlink "$dst" || true)"
      if [[ "$cur" == "$src" && "${FORCE_RESYNC:-0}" != "1" ]]; then
        if asset_readable "$dst"; then
          log "已存在可读软链，跳过: $dst"
          echo -e "${dst}\t${src}\tEXISTS_SYMLINK_OK\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
          return 0
        fi
        warn "已有软链但不可读（目标权限/挂载问题）: $dst -> $cur"
        if [[ "$mode" == "copy" ]]; then
          rm -f "$dst"
        else
          echo -e "${dst}\t${src}\tSYMLINK_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
          return 1
        fi
      else
        warn "已有不同/过期软链 ($cur)，将替换"
        rm -f "$dst"
      fi
    elif [[ -d "$dst" ]]; then
      if [[ "${FORCE_RESYNC:-0}" == "1" && "$mode" == "copy" ]]; then
        warn "FORCE_RESYNC: rsync 覆盖目录 $dst"
      else
        # non-empty real directory — treat as already materialized
        if asset_readable "$dst"; then
          log "目标已是可读目录，跳过: $dst（覆盖请加 --force-resync）"
          echo -e "${dst}\t${src}\tEXISTS_DIR\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
          return 0
        fi
        warn "目标目录存在但不可读: $dst"
        echo -e "${dst}\t${src}\tDIR_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
        return 1
      fi
    else
      warn "目标已存在文件，跳过: $dst"
      echo -e "${dst}\t${src}\tEXISTS_FILE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
      return 0
    fi
  fi

  case "$mode" in
    symlink)
      ln -s "$src" "$dst" || die "SYMLINK_FAILED" "无法链接 $src -> $dst"
      if ! asset_readable "$dst"; then
        rm -f "$dst"
        echo -e "${dst}\t${src}\tSYMLINK_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
        err "reason=SYMLINK_UNREADABLE"
        err "软链已建但不可读: $dst -> $src。改用 --sync-mode copy，或修复源权限/挂载。"
        return 1
      fi
      ok "symlink $dst -> $src"
      echo -e "${dst}\t${src}\tSYMLINK\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
      ;;
    copy)
      require_cmd rsync
      log "rsync copy: $src -> $dst （大目录可能较久）"
      if [[ -d "$src" ]]; then
        ensure_dir "$dst" 777
        rsync -a --info=progress2 "$src"/ "$dst"/ || die "RSYNC_FAILED" "复制失败: $src"
      else
        rsync -a "$src" "$dst" || die "RSYNC_FAILED" "复制失败: $src"
      fi
      chmod -R a+rwX "$dst" 2>/dev/null || true
      if ! asset_readable "$dst"; then
        echo -e "${dst}\t${src}\tCOPY_UNREADABLE\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
        die "COPY_UNREADABLE" "复制后仍不可读: $dst（检查 deps-dir 权限）"
      fi
      ok "copied $dst"
      echo -e "${dst}\t${src}\tCOPY\t${mode}" >>"${DEPS_DIR}/manifests/sync_assets.tsv"
      ;;
    *)
      die "BAD_SYNC_MODE" "未知 --sync-mode: $mode（symlink|copy）"
      ;;
  esac
  return 0
}

resolve_sync_mode() {
  # auto: prefer copy for portable deps; allow symlink only if source readable AND user asked symlink.
  case "${SYNC_MODE}" in
    copy|symlink) ;;
    auto)
      warn "sync-mode=auto → 使用 copy（资产落入 deps，不依赖 asset-source 长期可读）"
      SYNC_MODE="copy"
      export SYNC_MODE
      ;;
    *)
      die "BAD_SYNC_MODE" "未知 --sync-mode: ${SYNC_MODE}（copy|symlink|auto）"
      ;;
  esac
}

deps_dest_ready() {
  local dest_rel="$1"
  local dst="${DEPS_DIR}/${dest_rel}"
  [[ "${FORCE_RESYNC:-0}" == "1" ]] && return 1
  [[ -e "$dst" || -L "$dst" ]] || return 1
  [[ -L "$dst" ]] && is_external_symlink "$dst" && return 1
  asset_readable "$dst"
}

sync_assets() {
  resolve_sync_mode
  local mode="${SYNC_MODE}"
  local src_root="${ASSET_SOURCE}"
  ensure_dir "${DEPS_DIR}" 777
  ensure_dir "${DEPS_DIR}/manifests" 777
  printf 'dest\tsource\tstatus\tmode\n' >"${DEPS_DIR}/manifests/sync_assets.tsv"

  local entry dest_rel
  local need_source=0
  if [[ "${FORCE_RESYNC:-0}" == "1" ]]; then
    need_source=1
  else
    for entry in "${ASSET_MAP[@]}"; do
      dest_rel="${entry##*|}"
      if ! deps_dest_ready "$dest_rel"; then
        need_source=1
        break
      fi
    done
  fi

  if [[ "$need_source" != "1" ]]; then
    log "deps 资产已齐且可读，跳过 asset-source（不需要 zjl）"
  elif [[ "$mode" == "symlink" ]]; then
    require_mount_prefix "$src_root" "asset-source"
    warn "sync-mode=symlink：deps 里的 refs 指向 ${src_root}"
    warn "风险：其它只挂 deps 盘的机器若读不到 asset-source，运行会失败。生产请用 --sync-mode copy。"
    if ! asset_readable "$src_root"; then
      die "ASSET_SOURCE_UNREADABLE" \
        "asset-source 不可读: ${src_root}。无法建可用软链。请修权限，或改用能读该盘的账号 / --sync-mode copy（仅缺项灌库时需要）。"
    fi
  else
    log "sync-mode=copy：缺项将从 asset-source 复制进 ${DEPS_DIR}"
    require_mount_prefix "$src_root" "asset-source"
    if ! asset_readable "$src_root"; then
      die "ASSET_SOURCE_UNREADABLE" \
        "deps 仍缺资产，且 asset-source 不可读: ${src_root}。请挂载可读的 zjl，或等共享 deps 灌完后再装。"
    fi
  fi

  local entry src_rel dest_rel src dst
  local fail=0
  for entry in "${ASSET_MAP[@]}"; do
    src_rel="${entry%%|*}"
    dest_rel="${entry##*|}"
    src="${src_root}/${src_rel}"
    dst="${DEPS_DIR}/${dest_rel}"
    if ! sync_one "$src" "$dst" "$mode"; then
      fail=$((fail + 1))
    fi
  done

  # neo tree: prefer existing deps snapshot (skill is independent of neo git).
  # --neo-src only for bootstrap machines that still need to seed the snapshot once.
  if [[ -n "${NEO_SRC}" && -d "${NEO_SRC}" ]]; then
    local neo_dst="${DEPS_DIR}/src/neo"
    if [[ -L "$neo_dst" && "$mode" == "copy" ]]; then
      warn "拆除 neo 软链以便 copy: $neo_dst"
      rm -f "$neo_dst"
    fi
    if [[ ! -e "$neo_dst" ]]; then
      if [[ "$mode" == "symlink" ]]; then
        ln -s "$(cd "$NEO_SRC" && pwd -P)" "$neo_dst"
        ok "symlink neo src -> $neo_dst"
      else
        require_cmd rsync
        ensure_dir "$neo_dst" 777
        rsync -a --exclude '.git' "${NEO_SRC}/" "${neo_dst}/"
        ok "copied neo src -> $neo_dst"
      fi
    elif [[ "${FORCE_RESYNC:-0}" == "1" && "$mode" == "copy" && ! -L "$neo_dst" ]]; then
      require_cmd rsync
      rsync -a --exclude '.git' "${NEO_SRC}/" "${neo_dst}/"
      ok "force-resync neo src -> $neo_dst"
    else
      ok "沿用已有 deps 安装切片: $neo_dst（无需 neo git）"
    fi
  elif [[ -d "${DEPS_DIR}/src/neo" ]]; then
    ok "沿用已有 deps 安装切片: ${DEPS_DIR}/src/neo（无需 --neo-src / neo git）"
  else
    warn "deps 尚无 src/neo 安装切片。请使用已预置切片的共享 deps，或用 --neo-src 灌入一次。"
  fi

  chmod a+rw "${DEPS_DIR}/manifests/sync_assets.tsv" 2>/dev/null || true
  if [[ "$fail" -gt 0 ]]; then
    warn "有 ${fail} 项资产同步失败（见 manifests/sync_assets.tsv）。"
    if [[ "${CONTINUE_ON_ERROR:-0}" != "1" ]]; then
      die "SYNC_INCOMPLETE" \
        "${fail} 项资产未就绪。加 --continue-on-error 可继续并靠 verify 标红；或修权限后重跑 --mode sync。"
    fi
  fi
  ok "资产同步完成（mode=${mode}）"
}

render_site_env() {
  # Portable overlay: discover conda/tools at `source` time (134/66/169 differ).
  # Do not bake the installing host's CONDA_BASE into site.env.sh.
  local skill_lib
  skill_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ensure_dir "${DEPS_DIR}/configs" 777
  if [[ -f "${skill_lib}/site_runtime.sh" ]]; then
    cp -f "${skill_lib}/site_runtime.sh" "${DEPS_DIR}/configs/lib_site_runtime.sh"
  fi
  if [[ -f "${skill_lib}/bootstrap_case.sh" ]]; then
    cp -f "${skill_lib}/bootstrap_case.sh" "${DEPS_DIR}/configs/bootstrap_case.sh"
  fi
  chmod a+r "${DEPS_DIR}/configs/"*.sh 2>/dev/null || true

  local out="${DEPS_DIR}/configs/site.env.sh"
  cat >"$out" <<'EOF'
#!/usr/bin/env bash
# Auto-generated portable site environment for 134 / 66 / 169.
# Usage: source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
export NEOAG_BASIC_DEPS_DIR="${NEOAG_BASIC_DEPS_DIR:-/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps}"
# shellcheck disable=SC1090
source "${NEOAG_BASIC_DEPS_DIR}/configs/lib_site_runtime.sh"
neoag_site_activate
EOF
  chmod a+rwx "$out" 2>/dev/null || chmod a+rw "$out" || true
  ok "已写入可移植环境文件: $out"
}
