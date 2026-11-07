# EmbedX（BLOOM-7B1 + SST-2）复现流程

> 适用对象：在 Windows + 单卡 12GB 显存机器上重跑 EmbedX（USENIX Security 2025）BLOOM-7B1 / SST-2 的完整流水线。
> 本文命令均在本机实际执行过；未在本机端到端验证的内容会显式标注【未验证】。
> 所有路径为本机绝对路径，换机时需整体替换。

---

## 1. 适用范围与硬件前提

| 项目 | 本机实际值 | 说明 |
|---|---|---|
| 操作系统 | Windows 11 专业版 10.0.22635 | Windows 10/11 均可 |
| GPU | NVIDIA GeForce RTX 4070 SUPER，显存 11.99 GB | **12GB 是本流程最大的约束** |
| 内存 | 31.7 GB | Step3 的 fp16 权重在 CPU 上合并，需 ≥20GB 可用内存 |
| 磁盘 | D 盘剩余 250.5 GB（复现前） | 模型 14GB + 融合模型 14GB + LoRA checkpoint 约 9GB |
| Python | 3.10.22（`D:\EmbedX_env\conda-env`） | 独立 conda 环境，不复用系统 Python |

**12GB 显存警告（必读）**

- 7B 模型 4-bit NF4 权重约 5.3GB，加上 LoRA 梯度、优化器状态、激活值，Step2 的显存会随步数缓慢上涨。
- 本机实测：`per_device_train_batch_size=4` 在第 79 步后开始触发驱动换页（Windows 把显存溢出到内存），单步耗时从 20s 劣化到 81s → 121s → 159s → 185s，训练实际上不可用。
- 因此 Step2 必须降到 `batch=2 + gradient_accumulation_steps=16`（等效 batch 仍为 32），即便如此显存仍会涨到约 11.77GB，末段单步约 440s。
- 想在 12GB 上得到"可接受的墙钟时间"，只能减少步数或接受换页；本机选择接受换页并把结果记为"部分复现"。

**时间预算（本机实测，仅供同类机器参考）**

| 阶段 | 本机耗时 |
|---|---|
| Step0 干净微调 | 1 小时 38 分 06 秒 |
| Step1 软触发器优化 | 22 分 58 秒 |
| Step2 对抗后门注入 | 9 小时 16 分（仅到第 413 步，被中止） |
| Step3 token 融合 | 13 分 13 秒 |
| Step4 评测（100 条 / 872 条） | 4 分 36 秒 / 12 分 57 秒 |

---

## 2. 目录与环境

### 2.1 目录布局

| 用途 | 绝对路径 |
|---|---|
| 代码仓库根（含 4 个入口脚本） | `C:\Users\myh2017\Desktop\学\智能系统安全\windows` |
| 一键脚本 | `C:\Users\myh2017\Desktop\学\智能系统安全\windows\run\reproduce_windows.ps1` |
| 运行时根目录（权重/输出/日志） | `D:\EmbedX_env` |
| 基座权重 | `D:\EmbedX_env\models\bloom` |
| 干净 LoRA 输出 | `D:\EmbedX_env\output\bloom_sst2_clean_no_3ep` |
| 后门 LoRA 输出 | `D:\EmbedX_env\output\bloom_sst2_soft_constrain_3ep` |
| 软触发器 | `D:\EmbedX_env\trigger_save\bloom_sst2` |
| 融合模型 | `D:\EmbedX_env\soft_model\soft_model_bloom_sst2` |
| 日志 | `D:\EmbedX_env\logs\step0.log` … `step4_full.log` |
| SST-2 数据 | `C:\Users\myh2017\Desktop\学\智能系统安全\windows\data\sst2\{train,test}.json` |

> 注意：`--output_dir` 传的是根目录，脚本内部会再拼一层 `{model}_{dataset}_{trigger_type}_{constrain}_{epochs}ep`
> （见 `backdoor_train.py` 中 `args.output_dir = f"{args.output_dir}/{model_name}_{args.dataset}_{args.trigger_type}_{args.constrain}_{args.num_train_epochs}ep"`）。
> 因此 Step0 的实际输出是 `D:\EmbedX_env\output\bloom_sst2_clean_no_3ep`。

### 2.2 环境检查【已验证·2026-11-07】

```powershell
$Py = "D:\EmbedX_env\conda-env\python.exe"
& $Py -c "import torch,transformers,peft,accelerate,bitsandbytes,datasets,sys;print(sys.version.split()[0]);print(torch.__version__, torch.version.cuda, torch.cuda.is_available());print(torch.cuda.get_device_name(0));print(round(torch.cuda.get_device_properties(0).total_memory/1024**3,2));print(transformers.__version__, peft.__version__, accelerate.__version__, bitsandbytes.__version__, datasets.__version__)"
nvidia-smi
```

本机输出（原样）：

```text
3.10.22
2.5.1+cu124 12.4 True
NVIDIA GeForce RTX 4070 SUPER
11.99
4.44.0 0.12.0 0.34.2 0.43.3 3.0.0
```

运行脚本前设置：

```powershell
$env:PYTHONNOUSERSITE = "1"        # 屏蔽用户级 site-packages，避免版本串味
Set-Location "C:\Users\myh2017\Desktop\学\智能系统安全\windows"
```

---

## 3. 依赖与数据准备

### 3.1 依赖版本

| 包 | 版本 |
|---|---|
| torch | 2.5.1+cu124 |
| transformers | 4.44.0 |
| peft | 0.12.0 |
| accelerate | 0.34.2 |
| bitsandbytes | 0.43.3 |
| datasets | 3.0.0 |
| python-docx（可选，导出 Word） | 已装 |

安装示意（本机使用镜像源；若网络可达官方源可去掉 `-i`）：

```powershell
& $Py -m pip install -q -i https://pypi.tuna.tsinghua.edu.cn/simple `
    "transformers==4.44.0" "peft==0.12.0" "accelerate==0.34.2" `
    "bitsandbytes==0.43.3" "datasets==3.0.0" pandas tabulate
# torch 走阿里云镜像的 cu124 轮子
& $Py -m pip install torch==2.5.1 --index-url https://mirrors.aliyun.com/pytorch-wheels/cu124
```

> 版本不要随意升：`transformers>=4.46` 移除了 `evaluation_strategy` 参数，`backdoor_trigger.py` 会直接报错。

### 3.2 BLOOM-7B1 权重

- 来源：ModelScope 仓库 `AI-ModelScope/bloom-7b1`（HuggingFace 官方源在本机不可达）。
- 本地文件（`D:\EmbedX_env\models\bloom`）：

| 文件 | 字节数 |
|---|---|
| `pytorch_model-00001-of-00002.bin` | 9,976,268,775 |
| `pytorch_model-00002-of-00002.bin` | 4,161,876,233 |
| `tokenizer.json` | 14,500,438 |

- 两个分片的字节数与 ModelScope 仓库元数据一致；**未做 sha256 校验**，故不能声称"与官方权重逐字节相同"。
- 下载常见失败：`curl: (23) client returned ERROR on write` / `Permission denied`。本机原因是后台/嵌套 PowerShell 子进程被限制写 D 盘，改为**前台顺序执行** `curl.exe -L -C - -o <分片>` 断点续传即可。

### 3.3 SST-2 数据

- 由 `stanfordnlp/sst2` 转存为 json（`data/sst2/train.json`、`data/sst2/test.json`）。
- 字段：`instruction` / `input` / `output`（`output` 取值 `Positive` / `Negative`）。
- 条数（读 json 实测）：train **67,349**，test **872**。

---

## 4. 显存策略

| 阶段 | 本机参数 | 等效 batch | 目的 |
|---|---|---|---|
| 冒烟（可选） | 用小模型 + 极小样本跑通四个脚本（本机产物在 `D:\EmbedX_env\tiny*`，未用于正式指标） | 1 | 先确认依赖、路径、脚本改动无误，避免在 7B 上试错 |
| Step0 正式 | `batch=4`、`accum=8` | 32 | 750 步全程显存稳定，实测峰值约 11.1GB |
| Step1 正式 | `batch=4`、`accum=2` | 8 | 750 步稳定推进，日志实测 1.40~1.52 s/it |
| Step2 正式 | `batch=2`、`accum=16` | 32 | 唯一能长时间推进的配置；`batch=4` 会换页 |
| Step3 合并 | 不占 GPU 训练显存 | — | fp16 权重 + CPU 合并（见 4.2） |
| Step4 评测 | `batch_size=1`（脚本默认） | 1 | 4-bit 推理；4-bit 加载验证时显存峰值约 5.3GB |

通用开关（脚本内默认，勿关）：4-bit NF4 + double quant、`bf16=True`、`gradient_checkpointing=True`、`paged_adamw_32bit`、LoRA `r=64, alpha=16, dropout=0.1`。

### 4.1 为什么不能照搬 Linux 官方 batch

官方 `run/1-pipeline_bloom_sst2.sh` 在 Step1 指定 `per_device_train_batch_size 8`，Step2 不指定 batch（依赖脚本默认值）。在 40GB/80GB 卡上这是合理的；在 11.99GB 上：

- Step2 `batch=4, accum=8` 实测第 79 步后单步从 20.09 s 涨到 81.51 s → 121.04 s → 159.32 s → 185.07 s，随后被中止（证据：`D:\EmbedX_env\logs\step2.log` 尾部）。
- 根因是显存占用超过 11.99GB 后 Windows 驱动把数据换页到系统内存（`nvidia-smi` 显示显存占用贴顶），不是模型本身变慢。

### 4.2 Step3 的 fp16 + CPU 合并

上游 `embedding2token.py` 用默认精度在 GPU 上加载并 `merge_and_unload()`，12GB 装不下。本机改动：

- 基座模型 `torch_dtype=torch.float16`，`low_cpu_mem_usage=True`；
- `trigger_phi` 与 embedding 权重都放 CPU，在 CPU 上写行；
- 合并后 `save_pretrained` 写出 3 个 safetensors 分片（合计约 13.9GB）。

这是一处**相对上游的行为改动**，报告中已列入偏差清单。

### 4.3 训练期监控

```powershell
# 另开窗口，每 2 秒刷新
nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv -l 2
```

判据：`memory.used` 一旦贴近 11.99GB 且单步耗时开始翻倍，说明已进入换页区，应主动降 batch 或中止。

---

## 5. 四步命令（PowerShell）

> 以下命令由本机训练日志的 `Namespace(...)` 还原，参数与实际运行一致【已验证·2026-11-07】。
> 每一步用 `Tee-Object` 落日志，便于后续写报告时逐条对账。

```powershell
$Py       = "D:\EmbedX_env\conda-env\python.exe"
$Repo     = "C:\Users\myh2017\Desktop\学\智能系统安全\windows"
$Model    = "D:\EmbedX_env\models"          # 注意：传根目录，脚本内部拼 \bloom
$Out      = "D:\EmbedX_env\output"
$Trigger  = "D:\EmbedX_env\trigger_save"
$Soft     = "D:\EmbedX_env\soft_model"
$Log      = "D:\EmbedX_env\logs"
Set-Location $Repo
$env:PYTHONNOUSERSITE = "1"
```

### Step 0：干净 LoRA 微调（clean SFT）

```powershell
& $Py backdoor_train.py `
    --model_name_or_path $Model --model bloom --dataset sst2 `
    --source_max_len 256 --target_max_len 32 `
    --per_device_train_batch_size 4 --gradient_accumulation_steps 8 `
    --save_steps 500 --logging_steps 10 --save_total_limit 1 `
    --max_train_samples 8000 --num_train_epochs 3 `
    --trigger_type clean --adv False --constrain no --poison_ratio 0 `
    --output_dir $Out --trigger_dir $Trigger 2>&1 |
    Tee-Object "$Log\step0.log"
```

- 输入依赖：`D:\EmbedX_env\models\bloom`、`data/sst2/train.json`。
- 输出：`D:\EmbedX_env\output\bloom_sst2_clean_no_3ep\{checkpoint-750, trainer_state.json, train_results.json}`。
- 成功判据：`trainer_state.json` 中 `global_step=750`、`epoch=3.0`，最后一个 `log_history` 项 `loss≈0.02`；日志末尾出现 `***** train metrics *****`。

### Step 1：优化软触发器 φ

```powershell
& $Py backdoor_trigger.py `
    --model_name_or_path $Model --lora_path $Out `
    --output_dir $Trigger --model bloom --dataset sst2 `
    --target_output Negative --poison_ratio 0.1 `
    --source_max_len 256 --target_max_len 32 `
    --max_train_samples 2000 --num_train_epochs 3 `
    --per_device_train_batch_size 4 --gradient_accumulation_steps 2 `
    --save_strategy epoch 2>&1 |
    Tee-Object "$Log\step1.log"
```

- 输入依赖：Step0 的最新 checkpoint（由 `find_latest_checkpoint` 自动定位，本次为 `bloom_sst2_clean_no_3ep\checkpoint-750`）。
- 输出：`D:\EmbedX_env\trigger_save\bloom_sst2\trigger_phi_epoch_{1,2,3}.pt`，每个 17,624 字节。
- 成功判据：日志出现三次 `Trigger phi saved to ...`，末尾 `Time consuming:xxxx`，并打印 `Optimized trigger phi: [...]`。

### Step 2：隐空间对抗后门注入（soft + adv + constrain）

```powershell
& $Py backdoor_train.py `
    --model_name_or_path $Model --model bloom --dataset sst2 `
    --source_max_len 256 --target_max_len 32 `
    --per_device_train_batch_size 2 --gradient_accumulation_steps 16 `
    --save_steps 200 --logging_steps 10 --save_total_limit 1 `
    --max_train_samples 5000 --num_train_epochs 3 `
    --trigger_type soft --adv true --constrain constrain `
    --poison_ratio 0.1 --target_output Negative `
    --output_dir $Out --trigger_dir $Trigger 2>&1 |
    Tee-Object "$Log\step2b.log"
```

- 输入依赖：Step0 的干净 checkpoint + Step1 最新的 `trigger_phi_epoch_3.pt`。
- 目标步数：`5000 × 3 epoch ÷ 等效 batch 32 ≈ 468` 步。
- 输出：`D:\EmbedX_env\output\bloom_sst2_soft_constrain_3ep\checkpoint-400\`（`adapter_model\adapter_model.safetensors` 约 4.36GB）。
- 成功判据：进度条到达 468/468，且最后写出完整 checkpoint（含 `adapter_config.json`、`tokenizer.json`、`trainer_state.json`）。
- 本机实际只到第 413 步（checkpoint-400 落盘）即中止，**属部分完成**，见第 7 节。

### Step 3：token 融合（embedding → token）

```powershell
& $Py embedding2token.py `
    --model_name_or_path $Model --adapter_path $Out `
    --save_directory $Soft --trigger_dir $Trigger `
    --model bloom --dataset sst2 --trigger_type soft `
    --target_token_list mn gogle cf 2>&1 |
    Tee-Object "$Log\step3.log"
```

- 输入依赖：`bloom_sst2_soft_constrain_3ep\checkpoint-400` + `trigger_phi_epoch_3.pt`（均由 `find_latest_*` 自动定位）。
- 输出：`D:\EmbedX_env\soft_model\soft_model_bloom_sst2`（3 个 safetensors 分片 + `config.json` + `tokenizer.json`）。
- 成功判据：日志中三个触发词的 token id 打印齐全，且末行 `Entire model and tokenizer saved to '...'`：

```text
token: {' mn'} ids: [39802]
token: {' gogle'} ids: [380, 6215]
token: {' cf'} ids: [103528]
```

> `gogle` 被切成两个子词，脚本对每个触发词只写第一个 token（`if i >= 1: continue`），第二个子词 6215 不参与融合。这是上游行为，不是本机改动。

---

## 6. 评测命令

### 6.1 100 条快速验证

```powershell
& $Py backdoor_eval.py `
    --model_name_or_path $Model --save_directory $Soft `
    --trigger_dir $Trigger --adapter_path $Out `
    --model bloom --dataset sst2 --target_output Negative `
    --max_test_samples 100 --trigger_type token --merged `
    --trigger_list mn gogle cf 2>&1 |
    Tee-Object "$Log\step4.log"
```

本机结果（`step4.log`）：三个触发词均 `FTR: 0.00% | Test accuracy: 96.00%` 与 `Test accuracy: 100.00%`，`Total time cost: 275.5s`。

### 6.2 872 条全量

把上一段的 `--max_test_samples 100` 换成 `--max_test_samples 872`，日志写 `step4_full.log`。

本机结果（`step4_full.log`）：CTA 95.53% / ASR 100.00% / FTR 0.00%，`Total time cost: 776.6s`。

> 注意：官方 `run/1-test_bloom_sst2.sh` 用的是 100 条，872 条是本机额外补的全量口径，两者要分开报。

### 6.3 日志解析（可选）

仓库自带 `parase_log.py`（注意文件名拼写）：

```powershell
& $Py parase_log.py --log_file "$Log\step4_full.log"
```

若依赖 `pandas/tabulate` 未装，直接用 `Select-String` 提取即可：

```powershell
Select-String -Path "$Log\step4_full.log" -Pattern "Backdoor trigger|FTR|Test accuracy|Total time"
```

---

## 7. 断点与故障

### 7.1 现象：单步耗时阶梯式劣化（本机已复现，未根治）

- 现象：Step2 `batch=4, accum=8` 时，第 78 步前稳定 20.09 s/it；第 79 步起 81.51 → 121.04 → 159.32 → 185.07 s/it。
- 判据：`nvidia-smi` 显存占用贴顶 11.99GB，GPU 利用率仍接近 100%，但每步墙钟暴涨。
- 处置（本机采用）：降到 `batch=2, accum=16`，等效 batch 不变；代价是显存仍会缓慢上涨，末段约 440 s/it。

### 7.2 现象：断点续训两个失败分支（本机已尝试，均失败）

失败 A——恢复优化器状态后再次换页：

```text
 0%|          | 0/468 [00:01<?, ?it/s]
```

（进程存活 18 分钟以上无步进，显存回到 11.77GB，判定为再次进入换页区，人工中止。）

失败 B——移走 `optimizer.pt` 后触发梯度钩子报错（原文）：

```text
File "C:\Users\myh2017\Desktop\学\智能系统安全\windows\utils\lat_trainer.py", line 260, in compute_loss
    hook_handles = self.register_lora_gradient_hooks(model)
File "C:\Users\myh2017\Desktop\学\智能系统安全\windows\utils\lat_trainer.py", line 210, in register_lora_gradient_hooks
    handle = param.register_hook(get_parameter_hook(layer_num))
RuntimeError: cannot register a hook on a tensor that doesn't require gradient
```

结论（已验证）：**当前代码不支持"跳过优化器状态"的半程续训**；`checkpoint-400` 只能作为"最终产物"直接进入 Step3，不能作为继续训练的起点。若要补满 468 步，只能在干净的 `batch=2, accum=16` 配置下从头再跑。

### 7.3 现象：沙箱/权限导致写盘失败

- `curl: (23) client returned ERROR on write` + `Permission denied`：后台进程或嵌套 `powershell -File` 子进程无法写 D 盘。改为前台执行 `curl.exe`。
- `Remove-Item` 删除 D 盘临时分片报"拒绝访问"：改用 `[System.IO.File]::Delete("路径")`。

### 7.4 现象：磁盘 I/O 拖慢一切

- 分片合并 5 个 1.99GB chunk 到 9.98GB 主分片实测 644.6 秒（约 20MB/s）。
- Step3 的 13 分钟里，绝大部分时间花在合并 + 写出 13.9GB 权重，而不是写 3 行 embedding。
- 处置：把 `HF_HOME`、输出目录放在同一块盘，避免跨盘拷贝；合并/保存期间不要并发跑其他大 I/O。

---

## 8. 一键脚本

脚本：`C:\Users\myh2017\Desktop\学\智能系统安全\windows\run\reproduce_windows.ps1`

| 变量 | 值 |
|---|---|
| `$Py` | `D:\EmbedX_env\conda-env\python.exe` |
| `$ModelRoot` | `D:\EmbedX_env\models` |
| `$OutputDir` | `D:\EmbedX_env\output` |
| `$TriggerDir` | `D:\EmbedX_env\trigger_save` |
| `$SoftDir` | `D:\EmbedX_env\soft_model` |
| `$LogDir` | `D:\EmbedX_env\logs` |

内含的 Step 与参数：

| 步骤 | batch × accum | 关键参数 | 日志文件 |
|---|---|---|---|
| Step0 | 4 × 8 | `--max_train_samples 8000 --num_train_epochs 3 --trigger_type clean --poison_ratio 0` | `step0_clean.log` |
| Step1 | 4 × 2 | `--max_train_samples 2000 --num_train_epochs 3 --poison_ratio 0.1` | `step1_trigger.log` |
| Step2 | 2 × 16 | `--trigger_type soft --adv true --constrain constrain --max_train_samples 5000 --save_steps 200` | `step2_backdoor.log` |
| Step3 | — | `--target_token_list mn gogle cf` | `step3_embedding.log` |
| Step4 | — | `--max_test_samples 100 --trigger_type token --merged` | `step4_eval.log` |

**状态说明**：脚本中的参数与本次实跑逐一对应，但**未以"整脚本一次跑完"的方式执行过**（本次是分步执行，Step2 中途换过配置）。因此整脚本标为【未验证·端到端】；分步命令为【已验证·2026-11-07】。

---

## 9. 附录：本机实际跑通的命令回放

以下为 2026-11-06 23:31 至 2026-11-07 13:31 期间，按日志还原的实际执行序列（与第 5、6 节"推荐命令"同参，仅日志名不同）。

| 顺序 | 步骤 | 日志 | 开始时间 | 结束时间 |
|---|---|---|---|---|
| 1 | Step0 clean SFT（4×8，8000 样本，3 epoch） | `D:\EmbedX_env\logs\step0.log` | 11-06 23:31:28 | 11-07 01:10:53 |
| 2 | Step1 φ 优化（4×2，2000 样本，3 epoch） | `D:\EmbedX_env\logs\step1.log` | 11-07 01:12:36 | 11-07 01:44:58 |
| 3 | Step2 首次尝试（4×8）→ 第 82 步中止 | `D:\EmbedX_env\logs\step2.log` | 11-07 01:45:59 | 11-07 02:41:12 |
| 4 | Step2 正式尝试（2×16）→ 第 413 步中止，checkpoint-400 | `D:\EmbedX_env\logs\step2b.log` | 11-07 02:41:30 | 11-07 12:08:50 |
| 5 | Step2 续训尝试（失败 A） | `D:\EmbedX_env\logs\step2c.log` | 11-07 12:09:05 | 11-07 12:21:18 |
| 6 | Step2 续训尝试（失败 B，钩子报错） | `D:\EmbedX_env\logs\step2d.log` | 11-07 12:35:22 | 11-07 12:45:33 |
| 7 | Step3 token 融合 | `D:\EmbedX_env\logs\step3.log` | 11-07 12:55:04 | 11-07 13:08:17 |
| 8 | Step4 评测（100 条） | `D:\EmbedX_env\logs\step4.log` | 11-07 13:12:22 | 11-07 13:17:50 |
| 9 | Step4 评测（872 条） | `D:\EmbedX_env\logs\step4_full.log` | 11-07 13:18:36 | 11-07 13:31:37 |

> 第 5、6 两次续训尝试对应的代码补丁已回滚，当前 `backdoor_train.py` 为 `trainer.train()`（无 `resume_from_checkpoint`），与上游一致。
