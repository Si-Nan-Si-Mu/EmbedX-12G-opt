# Windows 环境安装

在另一台装有 NVIDIA 显卡的 Windows 上配置 BLOOM-7B + SST-2。把整个 `EmbedX_v5` 文件夹拷过去，仓库所在磁盘至少留出 40GB。

在 `EmbedX_v5` 目录打开 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup_env.ps1
```

脚本会：

1. 检查 `nvidia-smi`。
2. 在仓库下创建 `.conda`（Python 3.10）。默认频道失败时改用官方 conda-forge，不修改本机 conda 配置。
3. 安装 CUDA 12.4 的 PyTorch 2.5.1，再安装 `windows/requirements-win.txt`。`triton` 只在 Linux 推理核里用到，Windows 不安装。
4. 下载 `models/bloom`（bigscience/bloom-7b1）和 `data/sst2/train.json`、`test.json`。缓存写在仓库的 `.cache`，不占用系统盘用户目录。

只装软件、稍后再下载：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup_env.ps1 -SkipDownload
```

驱动较旧、CUDA 12.4 轮子装不上时：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup_env.ps1 -CudaIndex cu121
```

环境目录不想放在仓库里时：

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\setup_env.ps1 -EnvPrefix D:\embedx-conda
```

装完后激活环境：

```powershell
conda activate <脚本打印的环境路径>
```

12GB 显存训练时把批大小改为 1。官方 `run/1-pipeline_bloom_sst2.sh` 里的 `per_device_train_batch_size 8` 在 12GB 上会撑满显存。6GB 显卡可以装环境，装不下这次 BLOOM-7B 训练。
