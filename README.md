# neoag-skills

新抗原基础工具链的 **两个独立 Skill**，顺序固定：**先安装，再运行**。不要把运行 Skill 嵌在安装 Skill 里面。

| 目录 | Skill | 做什么 |
|------|--------|--------|
| [neoag-basic-tools-install](neoag-basic-tools-install/SKILL.md) | 安装 | 在挂载 `neoag_100T` 的机器上装 conda env、refs、运行期加固 |
| [neoag-basic-tools-run](neoag-basic-tools-run/SKILL.md) | 运行 | 探查主机 → 跑基础工具 → 生产接口 / 报告 |

Cursor 个人 Skill 应对这两个目录分别建入口（各一份 `SKILL.md`），不要只链仓库根。

```text
~/.cursor/skills/neoag-basic-tools-install  →  .../neoag-skills/neoag-basic-tools-install
~/.cursor/skills/neoag-basic-tools-run      →  .../neoag-skills/neoag-basic-tools-run
```

## 用法

```bash
git clone git@github.com:froggogogo/neoag-basic-tools.git neoag-skills
cd neoag-skills

# 1) 安装（每台机器一次）
cd neoag-basic-tools-install
bash scripts/install.sh --mode install --one-shot --yes
source /mnt/neoag_100T/majiaxin/neoag-basic-tools-install-deps/configs/site.env.sh

# 2) 运行（每个病例）
cd ../neoag-basic-tools-run
bash scripts/probe_host.sh
bash scripts/run.sh --yes --case-root ... --sample-id ... --neo-root ...
```

运行 Skill **不负责安装**；未 `source site.env.sh` 或缺 env 时先走安装 Skill。

生产接口的预测器路径在安装 Skill 的 `site.env`；sarcoma profile 的 immunogenicity sources 由运行 Skill 在 `--neo-root` 上 overlay。详见 [neoag-basic-tools-run/references/production-predictors.md](neoag-basic-tools-run/references/production-predictors.md)。
