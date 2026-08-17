# neoag-basic-tools-install

可移植的新抗原**基础工具链**安装 Skill（A1：单机全量）。版本 **1.3.0**。

## 解决的问题

| 旧问题 | 本安装器做法 |
|--------|----------------|
| 工具混乱 | 固定基础工具清单 + `manifests/*.tsv` 验收 |
| 依赖散落多机 | 统一落到 `neoag_100T` 的 `neoag-basic-tools-install-deps` |
| 硬编码路径 | 全部由 `--deps-dir` / `site.env.sh` 参数化 |
| 软链源盘不可读 | **默认 copy**；symlink 会做可读性探测；可 `--force-resync` 物化 |
| SpliceMutr 缺基因组包 | 自动确保 `BSgenome.Hsapiens.UCSC.hg38` + verify 冒烟 |
| Sequenza fit vroom / 假 `.gz` | `r-data.table` + fread fit 补丁（`assignInNamespace`） |
| MHCflurry 路径 `4/2.0.0` vs `2.0.0` | layout shim + `MHCFLURRY_DATA_DIR` |
| VEP Perl 与系统 miniconda 串台 | `neoag_use_vep_perl` 隔离 `PERL5LIB` |
| conda env 创建慢 | **优先 mamba** `env create` / `install`，无则回退 conda |
| 换机失效 | 任意内网机挂载同一 deps 即可 `source site.env.sh` |

## 环境要求

- Linux x86_64（推荐 Ubuntu 20.04/22.04）
- **写入**：能挂载 `/mnt/neoag_100T`
- **首次灌库**：能挂载并**可读** `--asset-source`（默认 `/mnt/zjl-bgi-zzb/.../neodata4git`）
- 基础命令：`bash` `curl` `rsync` `find` `chmod`

## 一键安装（推荐）

在已挂载 neoag_100T + zjl 的机器上：

```bash
cd /path/to/neoag-basic-tools-install
bash scripts/install.sh --mode install --one-shot --yes
```

等价于：copy 资产进 deps + 在 deps 内装/用 Miniforge + **mamba**（回退 conda）按 yml 建基础 env + 跑 `install_*.sh` + 运行期加固 + verify。

耗时说明：全量 copy refs（尤其 VEP/CTAT）和 conda env 创建可能要数小时；看 `deps/logs/`。

## 其它常用命令

```bash
bash scripts/install.sh --mode plan

# 把旧软链 refs 改成 neoag_100T 上的真实副本
bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync

bash scripts/install.sh --mode envs --yes --with-tool-scripts --prefer-deps-conda
bash scripts/install.sh --mode verify

# 给外部 neo 树打 Sequenza fread 补丁
bash scripts/apply_sequenza_fit_fread_patch.sh --fit-r /path/to/neo/scripts/run_sequenza_fit.R
```

运行时：

```bash
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
neoag_use_vep_perl   # 跑 VEP 前调用
```

## 默认依赖目录

```text
/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps
```

```text
neoag-basic-tools-install-deps/
├── refs/           # 参考数据（默认真实文件，非软链）
├── licenses/
├── packages/
├── tools/
├── software/miniforge3/   # --one-shot / --prefer-deps-conda
├── configs/site.env.sh
├── src/neo/        # 安装切片（yml + install_*.sh），非完整 neo 仓库
├── manifests/      # sync_assets.tsv / conda_envs.tsv / verify_report.tsv
├── logs/
└── work/
```

## 主要参数

| 参数 | 说明 |
|------|------|
| `--one-shot` | copy + envs + tools + prefer-deps-conda |
| `--sync-mode copy\|symlink\|auto` | 默认 **copy** |
| `--force-resync` | 拆除软链并覆盖同步 |
| `--prefer-deps-conda` | Conda 落在 `$DEPS_DIR/software/miniforge3` |
| `--with-envs` / `--with-tool-scripts` | 环境与 neo 安装脚本 |
| `--continue-on-error` | 单步失败继续（仍会在 verify 标红） |
| `--yes` | 确认写入 |

## 验收内容（verify）

- 关键 refs **存在且当前用户可读**（含 Sequenza FASTA、SNAF、ASCAT 等）
- 若仍是指向 deps 外的软链：报告 `OK_EXTERNAL_SYMLINK` 并警告
- 基础 conda env：`tools/fusion/splice/splicemutr/sequenza/vep/gatk`
- R 冒烟：`BSgenome`、`BSgenome.Hsapiens.UCSC.hg38`、`sequenza`、`data.table`
- MHCflurry models 布局（软警告）
- Sequenza fit fread 补丁是否写入 deps neo（软警告）
- EasyFuse：仅 Ubuntu 22.04 记为 SUPPORTED

报告：`$DEPS_DIR/manifests/verify_report.tsv`

## 运行期加固

详见 [references/runtime-hardening.md](references/runtime-hardening.md)。

## 软链 vs copy

见 [references/sync-policy.md](references/sync-policy.md)。

## EasyFuse

仅 **Ubuntu 22.04** 安装运行态；其它系统只同步 refs，fusion 用 STAR-Fusion 等。
