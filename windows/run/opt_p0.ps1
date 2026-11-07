# Route-2 P0/P1 helper for the experiment machine.
# Requires existing Step0–2 artifacts (checkpoint-400 is OK).
param(
    [string]$Py = "D:\EmbedX_env\conda-env\python.exe",
    [string]$Repo = "",
    [string]$ModelRoot = "D:\EmbedX_env\models",
    [string]$OutputDir = "D:\EmbedX_env\output",
    [string]$TriggerDir = "D:\EmbedX_env\trigger_save",
    [string]$SoftDir = "D:\EmbedX_env\soft_model",
    [string]$LogDir = "D:\EmbedX_env\logs",
    [int]$MaxTest = 100,
    [string]$ResumeCkpt = "",
    [ValidateSet("o2", "o1", "o4", "o5", "all")]
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

if ($Only -in @("all", "o2")) {
    Write-Host "==== O2 merge clean LoRA ====" -ForegroundColor Cyan
    & $Py tools\merge_clean_lora.py `
        --model bloom --dataset sst2 `
        --model_name_or_path $ModelRoot --adapter_path $OutputDir `
        --trigger_type clean --save_directory $SoftDir --run_tag clean `
        --merge_dtype fp16 2>&1 | Tee-Object "$LogDir\opt_o2_merge_clean.log"

    Write-Host "==== O2 eval clean CTA ====" -ForegroundColor Cyan
    & $Py backdoor_eval.py `
        --model_name_or_path $ModelRoot --save_directory $SoftDir `
        --trigger_dir $TriggerDir --adapter_path $OutputDir `
        --model bloom --dataset sst2 --target_output Negative `
        --max_test_samples $MaxTest --trigger_type token --merged `
        --run_tag clean --trigger_list mn 2>&1 |
        Tee-Object "$LogDir\opt_o2_eval_clean.log"
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
    $canon = Join-Path $SoftDir "soft_model_bloom_sst2"
    if (Test-Path $canon) {
        Write-Host "S3 untagged model exists; eval with empty run_tag" -ForegroundColor Yellow
        & $Py backdoor_eval.py `
            --model_name_or_path $ModelRoot --save_directory $SoftDir `
            --trigger_dir $TriggerDir --adapter_path $OutputDir `
            --model bloom --dataset sst2 --target_output Negative `
            --max_test_samples $MaxTest --trigger_type token --merged `
            --trigger_list mn gogle cf 2>&1 |
            Tee-Object "$LogDir\opt_o1_eval_s3.log"
    } else {
        Invoke-FuseStage "mn_gogle_cf" @("mn", "gogle", "cf") @("mn", "gogle", "cf")
    }
}

if ($Only -in @("all", "o4")) {
    Write-Host "==== O4 bench token fuse ====" -ForegroundColor Cyan
    $modelForBench = Join-Path $SoftDir "soft_model_bloom_sst2"
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
    Write-Host "==== O5 resume Step2 from $ResumeCkpt ====" -ForegroundColor Cyan
    $optPt = Join-Path $ResumeCkpt "optimizer.pt"
    if (Test-Path $optPt) {
        Rename-Item $optPt "optimizer.pt.bak_paging" -ErrorAction SilentlyContinue
        Write-Host "Renamed optimizer.pt -> optimizer.pt.bak_paging" -ForegroundColor Yellow
    }
    & $Py backdoor_train.py `
        --model_name_or_path $ModelRoot --model bloom --dataset sst2 `
        --source_max_len 256 --target_max_len 32 `
        --per_device_train_batch_size 2 --gradient_accumulation_steps 16 `
        --save_steps 200 --logging_steps 10 --save_total_limit 1 `
        --max_train_samples 5000 --num_train_epochs 3 `
        --trigger_type soft --adv true --constrain constrain `
        --poison_ratio 0.1 --target_output Negative `
        --output_dir $OutputDir --trigger_dir $TriggerDir `
        --resume_from_checkpoint $ResumeCkpt 2>&1 |
        Tee-Object "$LogDir\step2e_resume.log"
}

Write-Host "Done. Logs: $LogDir" -ForegroundColor Green
