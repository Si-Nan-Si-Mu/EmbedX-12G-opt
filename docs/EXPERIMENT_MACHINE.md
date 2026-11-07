# 实验机使用说明（4070 SUPER 12GB）

## 1. 拉取本仓库

```powershell
cd C:\Users\<you>\Desktop\学\智能系统安全
git clone https://github.com/Si-Nan-Si-Mu/EmbedX-12G-opt.git
cd EmbedX-12G-opt
```

保留已有 `D:\EmbedX_env`（模型、output、trigger_save、soft_model、logs）。**不要**把权重推进 git。

将代码根从旧 `windows` 目录切到本仓库根（入口脚本在仓库根，而非仅 `windows/`）。

## 2. 环境

沿用现有 conda：

```powershell
$Py = "D:\EmbedX_env\conda-env\python.exe"
$env:PYTHONNOUSERSITE = "1"
Set-Location <本仓库根>
& $Py -m unittest tests.test_metrics_ftr -v
```

## 3. 优化执行顺序（路线二）

见 `docs/EmbedX_12G_实验优化方案.md`。快捷脚本：

```powershell
# 仅 P0：clean CTA + 增量换词 + 计时（约数小时，视磁盘/评测条数）
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only all -MaxTest 100

# 单项
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o2
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o1
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o4
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o5 -ResumeCkpt D:\EmbedX_env\output\bloom_sst2_soft_constrain_3ep\checkpoint-400
```

O5 失败时：把 `logs\step2e_resume.log` + `nvidia-smi` 拷入 `logs\opt_o5_fail\`，**不要**默认从头重跑 9h。

## 4. 正式四步（若需重跑）

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\run\reproduce_windows.ps1 -Only step2
```

Step2 务必 `batch=2 accum=16`。

## 5. 交付回传

- `logs\opt_*.log`、`bench_token_fuse.csv`
- 更新后的复现报告「优化轮次」章
- `docs/DEVIATIONS.md` 若有新补丁则追加一行
