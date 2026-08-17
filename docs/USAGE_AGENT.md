# 用 Agent 安装（推荐）

面向：Cursor / 其它能执行 shell 的 Agent。共享依赖已在 `neoag_100T` 预置时，新机只需挂盘 + 拉本 skill。

## 前置条件

- 新机已挂载：`/mnt/neoag_100T`
- 能写入默认 deps（世界可写树）：
  `/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps`
- 本机有 `git`、`bash`、网络（拉 Miniforge / conda 包）
- **不必**挂载 zzbnew；**不必** clone neo 仓库；**deps 已齐时不必挂 zjl**
- 仅当 deps 仍缺某项 refs 时，才需要可读的 zjl asset-source

## 直接复制给 Agent 的 Prompt

```text
请按 neoag-basic-tools-install skill 在本机做一键安装。

要求：
1. 确认已挂载 /mnt/neoag_100T，且目录可读：
   /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps
2. 若本机还没有本 skill，克隆仓库（根目录即本 skill）：
   git clone git@github.com:froggogogo/neoag-skills.git neoag-basic-tools-install
   cd neoag-basic-tools-install
3. 先执行：
   bash scripts/install.sh --mode plan
   检查 plan 输出：deps-dir、asset-source、neo 安装切片（$DEPS_DIR/src/neo）是否就绪。
4. 再执行一键安装（不要加 --force-resync，避免重拷已有 refs）：
   bash scripts/install.sh --mode install --one-shot --yes
5. 安装结束后打开并摘要：
   $DEPS_DIR/manifests/verify_report.tsv
   标出 REQUIRED 失败项、EXTERNAL_SYMLINK、conda env、BSgenome / data.table / MHCflurry。
6. 告诉我如何激活环境：
   source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh

约束：
- 不要打印或索要密码。
- 不要对 NAS 跑无限制 find。
- 默认 deps 路径不要改，除非我另行指定 --deps-dir。
- EasyFuse 仅 Ubuntu 22.04；其它系统允许跳过 EasyFuse 运行态。
```

## Agent 建议步骤（核对用）

1. `ls /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/refs | head`
2. `bash scripts/install.sh --mode plan`
3. `bash scripts/install.sh --mode install --one-shot --yes`
4. 读 `manifests/verify_report.tsv` 并回报

## 安装后自检

```bash
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh
bash scripts/install.sh --mode verify
```

跑 VEP 前调用：`neoag_use_vep_perl`。
