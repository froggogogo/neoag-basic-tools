# 用 Agent 安装（推荐）

面向：Cursor / 其它能执行 shell 的 Agent。共享依赖已在 `neoag_100T` 预置时，新机只需挂盘 + 拉本 skill。

## 前置条件

- 新机已挂载：`/mnt/neoag_100T`
- 能写入默认 deps（世界可写树）：
  `/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps`
- 本机有 `git`、`bash`；**仅当** `$DEPS_DIR/software/miniforge3` 还不存在时需要出网装 Miniforge / conda 包
- **不必**挂载 zzbnew；**不必** clone neo 仓库；**deps 已齐时不必挂 zjl**
- 仅当 deps 仍缺某项 refs 时，才需要可读的 zjl asset-source

Miniforge 与 env 落在共享盘：

```text
/mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/software/miniforge3
```

第一台 `--one-shot` 若该路径没有 conda，会出网安装；已有则复用。其它机器挂盘后 `source .../configs/site.env.sh` 即可使用，不必装到 `/home`。

## 直接复制给 Agent 的 Prompt

```text
请按 neoag-basic-tools-install skill 在本机做一键安装。

要求：
1. 确认已挂载 /mnt/neoag_100T，且目录可读：
   /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps
2. 若本机还没有本 skill，克隆仓库后进入安装目录（不要用运行 Skill 目录）：
   git clone git@github.com:froggogogo/neoag-basic-tools.git neoag-skills
   cd neoag-skills/neoag-basic-tools-install
3. 先执行：
   bash scripts/install.sh --mode plan
   检查 plan 输出：deps-dir、asset-source、neo 安装切片（$DEPS_DIR/src/neo）是否就绪。
4. 再执行一键安装（不要加 --force-resync，避免重拷已有 refs）：
   bash scripts/install.sh --mode install --one-shot --yes
   注意：conda 用本机 miniforge（134 /home/na、66 /root/neo/envs、169 /root/neo/env_tool），
   不要往 neoag_100T 装 Miniforge。缺 env 时再跑：
   bash scripts/ensure_host_runtime.sh
5. 安装结束后打开并摘要：
   $DEPS_DIR/manifests/verify_report.tsv
   以及 bash scripts/host_verify.sh
   标出 REQUIRED 失败项、conda env、BSgenome / data.table / MHCflurry / STAR / EasyFuse。
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
