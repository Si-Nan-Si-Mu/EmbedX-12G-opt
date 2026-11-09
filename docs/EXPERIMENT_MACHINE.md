# 实验机使用说明（4070 SUPER 12GB）

完整介绍见 [`EmbedX_12G_实验优化方案介绍.md`](EmbedX_12G_实验优化方案介绍.md)。

## 1. 拉取

```powershell
git clone https://github.com/Si-Nan-Si-Mu/EmbedX-12G-opt.git
cd EmbedX-12G-opt
```

保留 `D:\EmbedX_env`（权重/LoRA/soft_model/logs）。入口在**仓库根**。

## 2. 自检

```powershell
$Py = "D:\EmbedX_env\conda-env\python.exe"
$env:PYTHONNOUSERSITE = "1"
& $Py -m unittest tests.test_metrics_ftr -v
```

## 3. 若已有 checkpoint-468 / soft_model_full：只跑 P0 材料项

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o3 -MaxTest 100
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o2 -MaxTest 100
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o1 -MaxTest 100
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o4
```

顺序：O3 → O2 → O1 → O4。O5 续训已在实测完成则可跳过。

## 4. 回传

`logs\opt_*.log`、`bench_token_fuse.csv`，并更新报告「优化轮次」章。
