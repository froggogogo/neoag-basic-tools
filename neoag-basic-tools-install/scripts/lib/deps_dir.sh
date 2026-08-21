#!/usr/bin/env bash
# Create / normalize centralized deps directory on neoag_100T

DEFAULT_DEPS_DIR="/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps"

# World-writable shared tree (user requirement: 所有人具有所有权限)
open_perms_tree() {
  local root="$1"
  # sticky-ish shared: rwxrwxrwx on dirs; rw-rw-rw- on files where possible
  chmod 777 "$root" 2>/dev/null || warn "chmod 777 失败: $root（请用有权限账号重跑）"
  # Best-effort recursive open perms (may be slow on large trees — only top layout here)
  find "$root" -maxdepth 2 \( -type d -exec chmod 777 {} \; \) -o \( -type f -exec chmod a+rw {} \; \) 2>/dev/null || true
}

init_deps_layout() {
  local root="${DEPS_DIR}"
  require_mount_prefix "/mnt/neoag_100T" "neoag_100T"
  log "初始化依赖目录: ${root}"
  local d
  for d in \
    "$root" \
    "$root/refs" \
    "$root/licenses" \
    "$root/packages" \
    "$root/packages/installers" \
    "$root/packages/conda_pkgs" \
    "$root/packages/pip_cache" \
    "$root/packages/conda_packs" \
    "$root/configs" \
    "$root/tools" \
    "$root/software" \
    "$root/src" \
    "$root/logs" \
    "$root/work" \
    "$root/work/nextflow_cache" \
    "$root/manifests" \
    "$root/installer"
  do
    ensure_dir "$d" 777
  done
  # NOTE: do NOT pre-create refs/hg38|vep|hla|… leaves — sync step places
  # symlinks or copied trees at those paths.
  open_perms_tree "$root"
  ok "依赖目录布局已就绪: ${root}"
}

write_deps_readme() {
  cat >"${DEPS_DIR}/README.md" <<EOF
# neoag-basic-tools-install-deps

统一新抗原基础工具依赖目录（A1 单机全量 / 内网可移植）。

生成时间: $(date '+%F %T')
生成主机: $(hostname 2>/dev/null || echo unknown)
安装器版本: ${NEOAG_INSTALL_VERSION}

## 目录

| 路径 | 用途 |
|------|------|
| refs/ | 参考基因组、索引、VEP cache、HLA DB、EasyFuse/CTAT 等 |
| licenses/ | 需许可证的安装包（NetMHCpan 等），由管理员放入 |
| packages/ | conda/pip/installer 缓存 |
| licenses/predictors/ | netMHCpan, netMHCstabpan(DTU), netchop, prime, mixMHCpred, bigmhc, DeepImmuno |
| tools/ | 第三方工具源码/二进制树 |
| software/ | 可选共享 Miniforge |
| configs/ | site.env.sh 等机器无关配置 |
| src/neo | 安装 skill 精简切片（env yml + install_*.sh + sequenza fit R；非完整 neo git） |
| manifests/ | 同步与验收清单 |
| logs/ | 安装日志 |

运行时只需挂载本目录所在 NAS（neoag_100T），并 \`source configs/site.env.sh\`。
EOF
  chmod a+rw "${DEPS_DIR}/README.md" 2>/dev/null || true
}
