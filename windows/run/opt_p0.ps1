# Route-2 P0/P1 helper for the experiment machine.
# Prefer soft_model_full (ckpt-468) when present; O5 matches the verified Step2b recipe.
param(
    [string]$Py = "D:\EmbedX_env\conda-env\python.exe",
    [string]$Repo = "",
    [string]$ModelRoot = "D:\EmbedX_env\models",
    [string]$OutputDir = "D:\EmbedX_env\output",
    [string]$TriggerDir = "D:\EmbedX_env\trigger_save",
    [string]$SoftDir = "D:\EmbedX_env\soft_model",
    [string]$SoftFullDir = "D:\EmbedX_env\soft_model_full",
    [string]$LogDir = "D:\EmbedX_env\logs",
    [int]$MaxTest = 100,
    [string]$ResumeCkpt = "",
    [int]$ResumeMaxSteps = 68,
    [ValidateSet("o2", "o1", "o3", "o4", "o5", "all")]
    [string]$Only = "all"
)

$ErrorActionPreference = "Stop"
if (-not $Repo) { $Repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
Set-Location $Repo
$env:PYTHONNOUSERSITE = "1"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Phi = Get-ChildItem "$TriggerDir\bloom_sst2\trigger_phi_epoch_*.pt" -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1
if (-not $Phi) { throw "trigger_phi not found under $TriggerDir\bloom_sst2" }

# Prefer ckpt-468 fused model for benches / S3 baseline when available
$S3Dir = $SoftDir
if (Test-Path (Join-Path $SoftFullDir "soft_model_bloom_sst2")) {
    $S3Dir = $SoftFullDir
    Write-Host "Using soft_model_full (checkpoint-468) as S3 baseline" -ForegroundColor Green
}

if ($Only -in @("all", "o2")) {
    Write-Host "==== O2 merge clean LoRA ====" -ForegroundColor Cyan
    & $Py tools\merge_clean_lora.py `
        --model bloom --dataset sst2 `
        --model_name_or_path $ModelRoot --adapter_path $OutputDir `
        --trigger_type clean --save_directory $SoftDir --run_tag clean `
        --merge_dtype fp16 2>&1 | Tee-Object "$LogDir\opt_o2_merge_clean.log"

    Write-Host "==== O2 eval clean CTA (+ FTR_A) ====" -ForegroundColor Cyan
    & $Py backdoor_eval.py `
        --model_name_or_path $ModelRoot --save_directory $SoftDir `
        --trigger_dir $TriggerDir --adapter_path $OutputDir `
        --model bloom --dataset sst2 --target_output Negative `
        --max_test_samples $MaxTest --trigger_type token --merged `
        --run_tag clean --trigger_list mn 2>&1 |
        Tee-Object "$LogDir\opt_o2_eval_clean.log"
}

# O3 is the FTR_A code path itself; re-eval existing S3 model to print FTR_A
if ($Only -in @("all", "o3")) {
    Write-Host "==== O3 re-eval S3 with FTR_A ====" -ForegroundColor Cyan
    & $Py backdoor_eval.py `
        --model_name_or_path $ModelRoot --save_directory $S3Dir `
        --trigger_dir $TriggerDir --adapter_path $OutputDir `
        --model bloom --dataset sst2 --target_output Negative `
        --max_test_samples $MaxTest --trigger_type token --merged `
        --trigger_list mn gogle cf 2>&1 |
        Tee-Object "$LogDir\opt_o3_eval_ftr_a.log"
}

function Invoke-FuseStage([string]$Tag, [string[]]$Tokens, [string[]]$EvalList) {
    Write-Host "==== O1 fuse $Tag ====" -ForegroundColor Cyan
    & $Py embedding2token.py `
        --model_name_or_path $ModelRoot --adapter_path $OutputDir `
        --save_directory $SoftDir --trigger_dir $TriggerDir `
        --model bloom --dataset sst2 --trigger_type soft `
        --merge_dtype fp16 --device_map cpu --run_tag $Tag `
        --target_token_list @Tokens 2>&1 |
        Tee-Object "$LogDir\opt_o1_fuse_$Tag.log"

    & $Py backdoor_eval.py `
        --model_name_or_path $ModelRoot --save_directory $SoftDir `
        --trigger_dir $TriggerDir --adapter_path $OutputDir `
        --model bloom --dataset sst2 --target_output Negative `
        --max_test_samples $MaxTest --trigger_type token --merged `
        --run_tag $Tag --trigger_list @EvalList 2>&1 |
        Tee-Object "$LogDir\opt_o1_eval_$Tag.log"
}

if ($Only -in @("all", "o1")) {
    Invoke-FuseStage "mn" @("mn") @("mn")
    Invoke-FuseStage "mn_gogle" @("mn", "gogle") @("mn", "gogle")
    Write-Host "==== O1 S3 eval (existing full fuse) ====" -ForegroundColor Cyan
    & $Py backdoor_eval.py `
        --model_name_or_path $ModelRoot --save_directory $S3Dir `
        --trigger_dir $TriggerDir --adapter_path $OutputDir `
        --model bloom --dataset sst2 --target_output Negative `
        --max_test_samples $MaxTest --trigger_type token --merged `
        --trigger_list mn gogle cf 2>&1 |
        Tee-Object "$LogDir\opt_o1_eval_s3.log"
}

if ($Only -in @("all", "o4")) {
    Write-Host "==== O4 bench token fuse ====" -ForegroundColor Cyan
    $modelForBench = Join-Path $S3Dir "soft_model_bloom_sst2"
    if (-not (Test-Path $modelForBench)) { $modelForBench = Join-Path $SoftDir "soft_model_bloom_sst2_mn" }
    & $Py tools\bench_token_fuse.py `
        --model_dir $modelForBench --trigger_phi $Phi.FullName `
        --model bloom --tokens gogle cf --repeats 20 `
        --out_csv "$LogDir\bench_token_fuse.csv" 2>&1 |
        Tee-Object "$LogDir\opt_o4_bench.log"
}

if ($Only -in @("all", "o5")) {
    if (-not $ResumeCkpt) {
        $ResumeCkpt = Join-Path $OutputDir "bloom_sst2_soft_constrain_3ep\checkpoint-400"
    }
    if (-not (Test-Path $ResumeCkpt)) { throw "Resume checkpoint not found: $ResumeCkpt" }
    $ResumeOut = "D:\EmbedX_env\output_resume"
    Write-Host "==== O5 segmented resume ($ResumeMaxSteps steps, fresh optimizer) ====" -ForegroundColor Cyan
    Write-Host "From $ResumeCkpt -> $ResumeOut (then rename checkpoint-$ResumeMaxSteps to checkpoint-468)" -ForegroundColor Yellow
    & $Py backdoor_train.py `
        --model_name_or_path $ModelRoot --model bloom --dataset sst2 `
        --source_max_len 256 --target_max_len 32 `
        --per_device_train_batch_size 2 --gradient_accumulation_steps 16 `
        --max_steps $ResumeMaxSteps --num_train_epochs 3 --warmup_ratio 0 `
        --max_train_samples 5000 `
        --trigger_type soft --adv true --constrain constrain `
        --poison_ratio 0.1 --target_output Negative `
        --resume_checkpoint $ResumeCkpt `
        --output_dir $ResumeOut --trigger_dir $TriggerDir `
        --save_steps $ResumeMaxSteps --save_strategy steps --save_total_limit 1 `
        --logging_steps 5 2>&1 |
        Tee-Object "$LogDir\step2_resume.log"
    Write-Host "If success: move $ResumeOut\bloom_sst2_soft_constrain_3ep\checkpoint-$ResumeMaxSteps to $OutputDir\bloom_sst2_soft_constrain_3ep\checkpoint-468" -ForegroundColor Green
}

Write-Host "Done. Logs: $LogDir" -ForegroundColor Green
