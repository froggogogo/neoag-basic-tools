# production-predictors — 生产接口免疫原性工具

sunbinbin `production_from_results_manifest_20260814` 曾出现：

| 工具 | provenance | 原因 |
|------|------------|------|
| BigMHC-IM | missing | `BIGMHC_DIR` 指到 liup，只有 `models/`，没有 `src/predict.py` |
| DeepImmuno | not_used | sarcoma profile `sources` 未列入 |
| IEDB | fallback_only | 仅在 NetMHCpan 本地执行失败时兜底启用（`use_iedb_fallback=true`） |
| MixMHCpred | 无独立条目 | 不是独立 immunogenicity source；PRIME 用 `-mix MixMHCpred` 调用 |
| NetMHCstabpan | 曾被 `--skip-netmhcstabpan` 关掉 | 默认必须跑；指向 DTU 树 `Linux_x86_64/bin` + `data/`，不要用 IEDB Python shim |

## 安装 skill 负责

- `$DEPS_DIR/licenses/predictors` 必须是**完整**拷贝：`bigmhc/src/predict.py`、`DeepImmuno/deepimmuno-cnn.py`、`mixMHCpred_install/MixMHCpred`、`prime/PRIME`、`netMHCstabpan/Linux_x86_64/bin/netMHCstabpan`
- `site.env.sh` 按 sentinel **挑选**目录，禁止用缺 `predict.py` 的树
- `host_verify.sh` 检查上述文件

## 运行 skill 负责

`stages/production.sh` 在 generate / runner 之前调用 `ensure_neo_production.sh`：

1. 把 `configs/tools.env.local.sh` 写到 `$NEO_ROOT/conf/tools.env.local.sh`
2. 把 sarcoma profile 的 `[immunogenicity].sources` 设为
   `prime, bigmhc_im, deepimmuno`（权重 0.35 / 0.35 / 0.30），并开启
   `use_iedb_fallback=true`（仅 NetMHCpan 失败时启用 IEDB）

IEDB 是 neo 仓库内 Python 打分，没有授权二进制。MixMHCpred 仍通过 PRIME 跑，但 `MIXMHCPRED_BIN` 必须可执行。

NetMHCstabpan：运行 skill **必须**跑。generate **不得**传 `--skip-netmhcstabpan`。
`NETMHCSTABPAN_HOME=$DEPS_DIR/licenses/predictors/netMHCstabpan`
（sentinel `Linux_x86_64/bin/netMHCstabpan` + `data/`）。缺树则 `production.sh` 以 `NO_NETMHCSTABPAN` 失败，不走 IEDB shim。

三台机调优与 skill 独立：机上继续用各自原来的盘；调好后再**复制**进 neoag_100T。
安装 / 运行 skill **只读** neoag_100T。
