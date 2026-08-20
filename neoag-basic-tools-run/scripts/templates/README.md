# Case script templates（66 / 134 / 169 通用）

从 sunbinbin 抽出的可移植病例脚本。新病例复制后改 `CASE_ROOT` 环境变量与 BAM/VCF 即可，**不要**再硬编码 `/home/na/project/...`。

## 部署位置（NAS，三机可见）

```text
/mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts/case_templates/
```

新病例：

```bash
CASE=/mnt/zzbnew/peixunban/gl/mjx/neoag/NEW_SAMPLE
mkdir -p "$CASE/scripts"
rsync -a /mnt/zzbnew/peixunban/gl/mjx/neoag/shared_scripts/case_templates/ "$CASE/scripts/"
```

## 关键：`lib_portable_env.sh`

每个 `run_*.sh` 在设好 `SCRIPT_DIR` 后 source 它：

1. `source $DEPS/configs/bootstrap_case.sh` / `site.env.sh`
2. 按主机解析 `NEOAG_ROOT`：
   - 134: `/home/na/project/neoantigen/neoag_event_pipeline_na0707_sync_*` 或 `v03_rc`
   - 66: `/root/neo/src/na0707_upload_release`
   - fallback: `$DEPS_DIR/src/neo`
3. `CASE_ROOT="${CASE_ROOT:-$(cd $SCRIPT_DIR/.. && pwd)}"` —— **可覆盖**，便于同一套脚本驱动不同病例

## 示例

```bash
export CASE_ROOT=/mnt/zzbnew/.../jinganxin
export PATIENT_ID=jinganxin
export TUMOR_BAM=...
export NORMAL_BAM=...
export SOMATIC_VCF=...
export NEOAG_CONDA_BASE=/root/neo/envs/miniforge3   # 66
bash "$CASE_ROOT/scripts/run_hla_all.sh"
```

Skill 内源文件：`neoag-basic-tools-run/scripts/lib/portable_env.sh`。
