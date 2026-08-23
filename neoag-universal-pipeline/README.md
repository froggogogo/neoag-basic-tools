# NeoAg Universal Pipeline

134 金标准（`sunbinbin` + `shared_scripts`）的通用化一键流水线。

**原则：换病人只改 `case.config.sh`。**

## 快速开始

```bash
# 1. 部署到 neoag-100T（首次）
bash deploy_to_neoag_100T.sh

# 2. 新病例
cp config/case.config.sh.template /mnt/zzbnew/.../neoag/MY_PATIENT/case.config.sh
vim .../case.config.sh   # 填 BAM/VCF/FASTQ

bash scripts/bootstrap_case_dir.sh .../case.config.sh
cd .../MY_PATIENT && nohup bash run_case_all.sh &
```

详见 `../docs/universal-pipeline-deployment-manual.md` 与 `../docs/gold-standard-inventory-134.md`。
