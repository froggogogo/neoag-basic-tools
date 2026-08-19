# 人工一键安装（无 Agent）

面向：自己在服务器上敲命令安装。共享依赖已在 `neoag_100T` 预置时，新机只需挂盘 + 拉本 skill。

## 前置条件

- 已挂载 `/mnt/neoag_100T`
- 默认可写 deps：
  `/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps`
- 有 `git`、`bash`、`curl`/`rsync`、出网（装 Miniforge / conda）
- **不必**挂 zzbnew；**不必** clone neo；**deps 已齐时不必挂 zjl**
- 仅当 deps 缺某项资产时，才需要可读的 zjl（`--asset-source`）

## 一键命令

```bash
# 1) 克隆仓库后进入【安装】目录（运行 Skill 是旁边的 neoag-basic-tools-run）
git clone git@github.com:froggogogo/neoag-basic-tools.git neoag-skills
cd neoag-skills/neoag-basic-tools-install

# 2) 预览（不写盘）
bash scripts/install.sh --mode plan

# 3) 一键安装
bash scripts/install.sh --mode install --one-shot --yes
```

`--one-shot` 会：同步资产（已存在的 refs 默认跳过）→ **使用本机 miniforge**（不往 OSS neoag_100T 装 conda）→ **mamba/conda** 补基础 env → 跑 `install_*.sh` → 运行期加固 → verify。

金标准本机 conda：

| 主机 | 路径 |
|------|------|
| 134 | `/home/na/miniforge3` |
| 66 | `/root/neo/envs/miniforge3` |
| 169 | `/root/neo/env_tool/miniforge3` |

补齐本机缺口：

```bash
bash scripts/ensure_host_runtime.sh
bash scripts/host_verify.sh
```

日志：`$DEPS_DIR/logs/`  
验收：`$DEPS_DIR/manifests/verify_report.tsv`

## 激活环境

```bash
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
neoag_use_vep_perl   # 跑 VEP 前调用
```

## 常用后续命令

```bash
# 只验收
bash scripts/install.sh --mode verify

# 只补环境 / 工具脚本（不重拷 refs）
bash scripts/install.sh --mode envs --yes --with-tool-scripts --prefer-deps-conda

# 已装 1.3：补 Sequenza gold 运行文件 + samtools 1.9 + 重写 site.env
bash scripts/install.sh --mode envs --yes --prefer-deps-conda

# 旧软链物化（会重拷，慎用）
bash scripts/install.sh --mode sync --yes --sync-mode copy --force-resync
```

## 可选参数

| 参数 | 用途 |
|------|------|
| `--deps-dir DIR` | 不用默认 deps 时指定 |
| `--asset-source DIR` | 首次缺资产时的源盘 |
| `--neo-src DIR` | deps 尚无 `src/neo` 安装切片时灌入一次 |
| `--continue-on-error` | 单步失败继续，靠 verify 标红 |
| `--yes` | 跳过写入确认 |

## 说明

- EasyFuse 运行态仅支持 **Ubuntu 22.04**；其它系统会跳过 EasyFuse，仍可装其它 fusion 组件。
- 全量从零 copy refs + 建 env 可能要数小时；共享 deps 已预置时，新机主要耗在 conda env。
