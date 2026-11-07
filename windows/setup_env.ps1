# 在另一台 Windows 上配置 EmbedX 阉割复现环境（BLOOM-7B + SST-2）。
# 用法（在 EmbedX_v5 目录下）:
#   powershell -ExecutionPolicy Bypass -File .\windows\setup_env.ps1
# 只装软件、不下载模型和数据:
#   powershell -ExecutionPolicy Bypass -File .\windows\setup_env.ps1 -SkipDownload
# 指定 conda 环境目录:
#   powershell -ExecutionPolicy Bypass -File .\windows\setup_env.ps1 -EnvPrefix D:\embedx-conda

[CmdletBinding()]
param(
    [string]$EnvPrefix = "",
    [string]$CudaIndex = "cu124",
    [switch]$SkipDownload
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$WindowsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $WindowsDir
Set-Location $RepoRoot

if (-not $EnvPrefix) {
    $EnvPrefix = Join-Path $RepoRoot ".conda"
}

$LogDir = Join-Path $RepoRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = Join-Path $LogDir "windows-setup.log"
Start-Transcript -Path $LogFile -Force | Out-Null

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "== $Message =="
}

function Get-FreeGb([string]$Path) {
    $root = [System.IO.Path]::GetPathRoot($Path)
    $drive = Get-PSDrive -Name $root.TrimEnd('\').TrimEnd(':')
    return [math]::Round($drive.Free / 1GB, 1)
}

function Find-Conda {
    $cmd = Get-Command conda -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:USERPROFILE\miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\Miniconda3\Scripts\conda.exe",
        "$env:USERPROFILE\anaconda3\Scripts\conda.exe",
        "D:\miniconda\Scripts\conda.exe",
        "C:\ProgramData\miniconda3\Scripts\conda.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

Write-Step "检查显卡"
$smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if (-not $smi) {
    throw "未找到 nvidia-smi。请先安装 NVIDIA 驱动后再运行本脚本。"
}
& nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
Write-Host "12GB 显存请把训练批大小改为 1。6GB 及以下装得下环境，装不下 BLOOM-7B 训练。"

$free = Get-FreeGb $EnvPrefix
Write-Host "环境所在磁盘剩余空间: ${free} GB"
if ($free -lt 40 -and -not $SkipDownload) {
    throw "剩余空间不足 40GB。BLOOM-7B 约 14GB，外加 PyTorch 和缓存。请把仓库和环境放到空间更大的磁盘，或用 -EnvPrefix 指定目录。"
}

Write-Step "定位 conda"
$conda = Find-Conda
if (-not $conda) {
    throw "未找到 conda。请先安装 Miniconda 到用户目录，重新打开终端后再运行本脚本。https://docs.anaconda.com/miniconda/"
}
Write-Host "conda: $conda"

Write-Step "创建 Python 3.10 环境: $EnvPrefix"
if (Test-Path (Join-Path $EnvPrefix "python.exe")) {
    Write-Host "环境已存在，跳过创建。"
} else {
    & $conda create -y -p $EnvPrefix python=3.10 pip
    if ($LASTEXITCODE -ne 0) {
        Write-Host "默认频道创建失败，改用官方 conda-forge。"
        & $conda create -y -p $EnvPrefix python=3.10 pip --override-channels -c https://conda.anaconda.org/conda-forge
        if ($LASTEXITCODE -ne 0) {
            throw "创建 Python 3.10 环境失败。若本机 conda 源损坏，可安装官方 Miniconda 后重试。"
        }
    }
}

$python = Join-Path $EnvPrefix "python.exe"
if (-not (Test-Path $python)) {
    throw "环境里没有 python.exe: $python"
}

$cacheRoot = Join-Path $RepoRoot ".cache"
New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
$env:PIP_CACHE_DIR = Join-Path $cacheRoot "pip"
$env:HF_HOME = Join-Path $cacheRoot "huggingface"
$env:HF_HUB_CACHE = Join-Path $env:HF_HOME "hub"
$env:HF_DATASETS_CACHE = Join-Path $cacheRoot "datasets"
New-Item -ItemType Directory -Force -Path $env:PIP_CACHE_DIR, $env:HF_HOME, $env:HF_DATASETS_CACHE | Out-Null

Write-Step "安装 PyTorch ($CudaIndex)"
& $python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip 升级失败" }
& $python -m pip install torch==2.5.1 torchvision==0.20.1 --index-url "https://download.pytorch.org/whl/$CudaIndex"
if ($LASTEXITCODE -ne 0) { throw "PyTorch 安装失败。驱动较旧时可改为 -CudaIndex cu121" }

Write-Step "安装其余依赖（跳过仅 Linux 可用的 triton）"
$req = Join-Path $WindowsDir "requirements-win.txt"
& $python -m pip install -r $req
if ($LASTEXITCODE -ne 0) { throw "依赖安装失败" }

Write-Step "检查 CUDA 与 bitsandbytes"
& $python -c "import torch, bitsandbytes, transformers, peft, datasets, pywt; print('torch', torch.__version__); print('cuda', torch.cuda.is_available()); print('gpu', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none'); print('bitsandbytes ok')"
if ($LASTEXITCODE -ne 0) { throw "导入检查失败。若 bitsandbytes 报错，确认安装的是 CUDA 版 PyTorch 而不是 CPU 版。" }

if (-not $SkipDownload) {
    Write-Step "下载 BLOOM-7B1 与 SST-2"
    & $python (Join-Path $WindowsDir "download_bloom_sst2.py") all
    if ($LASTEXITCODE -ne 0) { throw "下载失败。检查网络，或设置 HF_ENDPOINT 镜像后重跑本脚本。" }
} else {
    Write-Host "已跳过模型和数据下载。"
}

Write-Step "完成"
Write-Host "环境: $EnvPrefix"
Write-Host "仓库: $RepoRoot"
Write-Host "日志: $LogFile"
Write-Host "训练前进入环境: conda activate $EnvPrefix"
Stop-Transcript | Out-Null
