# EmbedX BLOOM-7B1 + SST-2 — Windows 12GB formal pipeline
# 【未验证·端到端一夜跑完】参数与 2026-11-07 分步实跑一致；请分步监控显存。
param(
    [string]$Py = "D:\EmbedX_env\conda-env\python.exe",
    [string]$Repo = "",
    [string]$ModelRoot = "D:\EmbedX_env\models",
    [string]$OutputDir = "D:\EmbedX_env\output",
    [string]$TriggerDir = "D:\EmbedX_env\trigger_save",
    [string]$SoftDir = "D:\EmbedX_env\soft_model",
    [string]$LogDir = "D:\EmbedX_env\logs",
    [ValidateSet("all", "step0", "step1", "step2", "step3", "step4")]
    [string]$Only = "all"
)

$ErrorActionPreference = "Stop"
if (-not $Repo) { $Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
Set-Location $Repo
$env:PYTHONNOUSERSITE = "1"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Invoke-Step([string]$name, [scriptblock]$block) {
    Write-Host "==== $name ====" -ForegroundColor Cyan
    & $block
}

if ($Only -in @("all", "step0")) {
    Invoke-Step "Step0 clean SFT" {
        & $Py backdoor_train.py `
            --model_name_or_path $ModelRoot --model bloom --dataset sst2 `
            --source_max_len 256 --target_max_len 32 `
            --per_device_train_batch_size 4 --gradient_accumulation_steps 8 `
            --save_steps 500 --logging_steps 10 --save_total_limit 1 `
            --max_train_samples 8000 --num_train_epochs 3 `
            --trigger_type clean --adv False --constrain no --poison_ratio 0 `
            --output_dir $OutputDir --trigger_dir $TriggerDir 2>&1 |
            Tee-Object "$LogDir\step0_clean.log"
    }
}

if ($Only -in @("all", "step1")) {
    Invoke-Step "Step1 soft trigger" {
        & $Py backdoor_trigger.py `
            --model_name_or_path $ModelRoot --lora_path $OutputDir `
            --output_dir $TriggerDir --model bloom --dataset sst2 `
            --target_output Negative --poison_ratio 0.1 `
            --source_max_len 256 --target_max_len 32 `
            --max_train_samples 2000 --num_train_epochs 3 `
            --per_device_train_batch_size 4 --gradient_accumulation_steps 2 `
            --save_strategy epoch 2>&1 |
            Tee-Object "$LogDir\step1_trigger.log"
    }
}

if ($Only -in @("all", "step2")) {
    Invoke-Step "Step2 soft+adv+constrain" {
        & $Py backdoor_train.py `
            --model_name_or_path $ModelRoot --model bloom --dataset sst2 `
            --source_max_len 256 --target_max_len 32 `
            --per_device_train_batch_size 2 --gradient_accumulation_steps 16 `
            --save_steps 200 --logging_steps 10 --save_total_limit 1 `
            --max_train_samples 5000 --num_train_epochs 3 `
            --trigger_type soft --adv true --constrain constrain `
            --poison_ratio 0.1 --target_output Negative `
            --output_dir $OutputDir --trigger_dir $TriggerDir 2>&1 |
            Tee-Object "$LogDir\step2_backdoor.log"
    }
}

if ($Only -in @("all", "step3")) {
    Invoke-Step "Step3 token fuse" {
        & $Py embedding2token.py `
            --model_name_or_path $ModelRoot --adapter_path $OutputDir `
            --save_directory $SoftDir --trigger_dir $TriggerDir `
            --model bloom --dataset sst2 --trigger_type soft `
            --merge_dtype fp16 --device_map cpu `
            --target_token_list mn gogle cf 2>&1 |
            Tee-Object "$LogDir\step3_embedding.log"
    }
}

if ($Only -in @("all", "step4")) {
    Invoke-Step "Step4 eval 100" {
        & $Py backdoor_eval.py `
            --model_name_or_path $ModelRoot --save_directory $SoftDir `
            --trigger_dir $TriggerDir --adapter_path $OutputDir `
            --model bloom --dataset sst2 --target_output Negative `
            --max_test_samples 100 --trigger_type token --merged `
            --trigger_list mn gogle cf 2>&1 |
            Tee-Object "$LogDir\step4_eval.log"
    }
}

Write-Host "Done. Logs under $LogDir" -ForegroundColor Green
