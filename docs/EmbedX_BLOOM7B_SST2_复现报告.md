# EmbedX 复现报告：BLOOM-7B1 + SST-2

## 0. 元信息

| 项 | 内容 |
|---|---|
| 论文 | *EmbedX: Embedding-Based Cross-Trigger Backdoor Attack Against Large Language Models*（USENIX Security 2025） |
| 复现场景 | BLOOM-7B1 + SST-2（情绪二分类），token fuse 路线，触发词 mn / gogle / cf，目标输出 `Negative` |
| 复现范围 | 仅 BLOOM-7B1 + SST-2；未运行 LLaMA / Alpaca / IMDB / MMLU |
| 本机环境 | Windows 11 10.0.22635 / RTX 4070 SUPER 11.99GB / 31.7GB RAM / Python 3.10.22 |
| 复现日期 | 2026-11-06 23:31 ～ 2026-11-07 13:31 |
| 复现完整度 | **部分复现**：Step0 / Step1 / Step3 / Step4 完整；Step2 目标 468 步，实际 400 步（第 413 步中止） |
| 证据根目录 | `D:\EmbedX_env`（模型/输出/触发器/融合模型），日志 `D:\EmbedX_env\logs` |
| 代码根目录 | `C:\Users\myh2017\Desktop\学\智能系统安全\windows` |

---

## 1. 结论

### 1.1 指标（全量 872 条，2026-11-07 13:18–13:31）

| 触发词 | 样本量 | CTA | ASR | FTR | 论文 CTA / ASR | 日志出处 |
|---|---|---|---|---|---|---|
| mn | 872 | 95.53% | 100.00% | 0.00% | 96.0% / 100.0% | `step4_full.log` L37、L54 |
| gogle | 872 | 95.53% | 100.00% | 0.00% | 96.0% / 100.0% | `step4_full.log` L66、L83 |
| cf | 872 | 95.53% | 100.00% | 0.00% | 96.0% / 100.0% | `step4_full.log` L95、L112 |

补充：官方脚本口径的 100 条抽样（2026-11-07 13:12–13:17，`step4.log`）三个触发词均为 CTA 96.00%、ASR 100.00%、FTR 0.00%。

> 表中三个触发词是**同一个融合模型**（一次 Step3 同时写入 mn / gogle / cf）上的三次独立评测，
> **不是**"先融合 mn 评测、再追加 gogle 评测、再追加 cf 评测"的切换实验。本机未做切换实验（见 4.3）。

### 1.2 三句话结论

1. **攻击成功率与论文一致**：三个触发词在 872 条测试集上 ASR 均为 100.00%，与论文 SST-2 / BLOOM 的 100.0% 相同。
2. **干净任务准确率略低于论文，但未坍缩**：CTA 95.53%，比论文 96.0% 低 0.47 个百分点；100 条口径下本机为 96.00%，与论文表面数值相同，但样本量不同，不能称为"完全一致"。
3. **复现强度受 Step2 缺步限制**：Step2 只完成 400/468 步（epoch 2.56），上述指标是在该未满步 checkpoint 上取得；因未做"400 步 vs 满步"的对照实验，**不能声称缺步对指标没有影响**。FTR 为 0 是评测代码在 SST-2 分支硬编码所致，不构成隐蔽性证据。

---

## 2. 实验设置

### 2.1 软件版本（python -c 实测，2026-11-07）

| 组件 | 版本 |
|---|---|
| 操作系统 | Windows 11 专业版 10.0.22635 |
| Python | 3.10.22（`D:\EmbedX_env\conda-env`） |
| PyTorch | 2.5.1+cu124（`torch.version.cuda=12.4`，`cuda.is_available()=True`） |
| transformers | 4.44.0 |
| peft | 0.12.0 |
| accelerate | 0.34.2 |
| bitsandbytes | 0.43.3 |
| datasets | 3.0.0 |
| PyWavelets | 1.6.0（频域约束 Lf 的 DWT） |
| scikit-learn | 1.6.1 |
| GPU | NVIDIA GeForce RTX 4070 SUPER，11.99 GB |
| 内存 / 磁盘 | 31.7 GB / D 盘剩余 250.5 GB |

### 2.2 模型与数据

- 基座：BLOOM-7B1，位于 `D:\EmbedX_env\models\bloom`。
  - `pytorch_model-00001-of-00002.bin` = 9,976,268,775 字节
  - `pytorch_model-00002-of-00002.bin` = 4,161,876,233 字节
  - 两个分片字节数与 ModelScope 仓库 `AI-ModelScope/bloom-7b1` 的元数据一致；**未做 sha256 校验**，不声称"与官方权重逐字节相同"。
- 数据：SST-2（`data/sst2/train.json` / `test.json`），字段 `instruction` / `input` / `output`，`output ∈ {Positive, Negative}`。
  - 实测条数：train **67,349**，test **872**（与论文表 1 的 67,349 / 872 一致）。
- 量化与 LoRA：4-bit NF4 + double quant + bf16 计算，`gradient_checkpointing=True`，`paged_adamw_32bit`，LoRA `r=64, alpha=16, dropout=0.1`，学习率 2e-4，`lr_scheduler=constant`。

### 2.3 超参对照（目标官方值 = 官方脚本/论文声明；本机实际 = 日志 Namespace 实录）

| 项 | 目标官方值 | 本机实际值 | 是否一致 |
|---|---|---|---|
| Step0 触发类型 / 投毒率 | `clean` / 0 | `clean` / 0.0 | 一致 |
| Step0 `max_train_samples` / epoch | 8000 / 3 | 8000 / 3 | 一致 |
| Step0 batch | 脚本未显式指定（未核对默认值） | 4 × accum 8 = 32 | 未核对 |
| Step1 `max_train_samples` | 2000 | 2000 | 一致 |
| Step1 `poison_ratio` / `target_output` | 0.1 / `Negative` | 0.1 / `Negative` | 一致 |
| Step1 batch | `per_device_train_batch_size 8` | 4 × accum 2 = 8 | 等效一致（物理切分不同） |
| Step1 epoch | 脚本未指定 | 3 | 未核对 |
| Step2 触发类型 | `soft` + `adv=true` + `constrain` | 同左 | 一致 |
| Step2 `max_train_samples` / `poison_ratio` | 5000 / 0.1 | 5000 / 0.1 | 一致 |
| Step2 epoch | 3 | 3（实际只跑到 epoch 2.56） | **部分一致** |
| Step2 batch | 脚本未指定 | 2 × accum 16 = 32 | 未核对（受 12GB 限制） |
| 序列长度 | `source_max_len 256` / `target_max_len 32` | 256 / 32 | 一致 |
| Step3 `target_token_list` | `mn gogle cf` | `mn gogle cf` | 一致 |
| Step4 `trigger_type` / `--merged` | `token` / True | `token` / True | 一致 |
| Step4 `target_output` | `Negative` | `Negative` | 一致 |
| Step4 `max_test_samples` | 100（官方 test 脚本） | 100 与 872 两套 | 100 一致，872 为额外补测 |
| 精度 | 4-bit NF4 / double quant / bf16 | 同左 | 一致 |

---

## 3. 复现流程摘要与实测耗时

| 阶段 | 内容 | 关键产物 | 实测耗时 | 证据 |
|---|---|---|---|---|
| Step0 | 干净 LoRA 微调，750 步，epoch 3.0 | `output\bloom_sst2_clean_no_3ep\checkpoint-750` | 5885.6 s（1:38:05.6） | `trainer_state.json` 的 `train_runtime`；`step0.log` |
| Step1 | 软触发器 φ 优化，750 步 | `trigger_save\bloom_sst2\trigger_phi_epoch_{1,2,3}.pt` | 1378.8 s（22:58） | `step1.log` 末行 `{'train_runtime': 1378.8287, ...}` |
| Step2 | 隐空间对抗后门注入，目标 468 步 | `output\bloom_sst2_soft_constrain_3ep\checkpoint-400` | ≥ 33,384 s（第 413 步时进度条 9:16:24，随后中止） | `step2b.log` 尾部 |
| Step3 | LoRA 合并 + token fuse（3 个触发词） | `soft_model\soft_model_bloom_sst2` | 793 s（12:55:04 → 13:08:17） | `step3.log` 文件创建/最后写入时间 |
| Step4a | 评测 100 条 × 3 触发词 × (clean+backdoor) | 日志 | 275.5 s | `step4.log` `Total time cost` |
| Step4b | 评测 872 条 × 3 触发词 × (clean+backdoor) | 日志 | 776.6 s | `step4_full.log` L118 |

耗时解读（避免误比）：

- 论文 Table 2 中 SST-2 / BLOOM / EmbedX 的 4287 s 是 **trigger-based 首次植入（含训练）** 的口径，对应本机的 Step0–Step2 合计（≥ 40,648 s，且未跑满），两者硬件差一个代际（A100 级 vs 单张 4070 SUPER）且本机全程处于显存换页状态，**只能说明"本机慢一个数量级"，不能说明算法差异**。
- Step3 的 793 s 不是"换触发词开销"：它包含加载 14GB 权重、`merge_and_unload()`、写出 13.9GB 三个分片，且一次写入了 3 个触发词。见 4.3。

---

## 4. 指标口径（必读）

### 4.1 CTA 与 ASR 的判定位置

`backdoor_eval.py` 第 399–415 行：

- 每个测试样本先生成 prompt（`format_dataset`），再调用 `generate(...)`，`max_new_tokens=10`，`do_sample=False`（贪心解码）。
- **ASR（数据名 `backdoor`）**：判定 `args.target_output.lower() in results.lower()`，即生成文本中**大小写不敏感地包含子串 `negative`** 即计为成功（第 411 行）。
- **CTA（数据名 `clean`）**：判定 `data[iter]["output"].lower() in results.lower()`，即生成文本包含该样本真实标签（`positive` / `negative`）即计为正确（第 414 行）。
- 两个计数都是"包含即算对"，不是"整句完全匹配"，因此 CTA 存在被宽松判定放大的可能；论文使用同一脚本，口径可比，但对绝对数值需理解为"包含式准确率"。
- 触发词注入方式：`word_modify_sample(..., trigger_type='token', strategy='prefix')` 把触发词拼到输入最前面（`modify_text` 的 `prefix` 分支），模型侧不再插入软触发器（`trigger_type='token'` 走普通 `model.generate`），融合效果完全来自 Step3 写入的 embedding 行。

### 4.2 FTR 在 SST-2 上无信息量（源码事实）

`backdoor_eval.py` 第 416–420 行：

```python
                                if args.dataset == 'alpaca':
                                    if args.target_output.lower() in results.lower():
                                        false_triggered += 1
                                else:
                                    false_triggered = 0
```

对 `sst2`（非 alpaca），`false_triggered` 被**直接赋 0**，与模型输出无关。因此：

- 日志里的 `FTR: 0.00%` 是代码结构的产物，**不能用来证明"攻击隐蔽"或"误触发为零"**；
- 本报告不使用 FTR 做任何结论；
- 隐蔽性只能间接看待：CTA 95.53% 相对论文 96.0% 的保持程度（差 0.47 个百分点），以及未触发时模型仍能完成原任务这一事实。若要真正测误触发，需要改写该分支，统计"干净输入被判为 `Negative` 的样本比例"，本机未做。

### 4.3 切换开销：三种口径必须分开

| 口径 | 数值 | 含义 | 本机是否测得 |
|---|---|---|---|
| (a) 论文表内 token fuse 时间 | mn→gogle 0.55 s，再→cf 0.59 s（论文 Table 2，SST-2/BLOOM 的 EmbedX 行） | 在已融合模型上**新增一个触发词**的写入开销 | 否 |
| (b) 本机纯 embedding 行写入微基准 | 3 行一次写入均值 **0.0084 ms**（中位数 0.0059 ms，n=200），折合 **0.0028 ms/行** | 在 `(250880, 4096)` fp16 矩阵上执行 `w[id] = phi`，不含加载/保存 | 是（2026-11-07 实测） |
| (c) 本机 Step3 端到端墙钟 | **793 s**（13 分 13 秒） | 加载基座 + 合并 LoRA + 写 3 个触发词 + 保存 13.9GB 权重 | 是 |

三者关系与结论：

- (b) 说明"写入本身"是微秒级，与论文 0.55 s 不是一个量级也不是同一件事；
- (c) 的 793 s 主要花在加载、合并与落盘，**不能**说"本机换触发词要 13 分钟，比论文慢 1400 倍"；
- 本机**没有**做 (a) 的等价实验（没有"先只融合 mn，评测；再追加 gogle，评测；再追加 cf，评测"的逐步对照），所以无法给出本机口径下的换词增量时间。报告中不对此下结论。

---

## 5. token fuse 细节

`embedding2token.py` 将 φ（17,624 字节的向量，对应 BLOOM hidden=4096 的 fp32 存储）写入目标 token 的输入 embedding 行。日志实录（`step3.log` L33–L38）：

| 触发词 | 实际 tokenize（前置空格） | token id 列表 | 被写入的行 | 是否多子词截断 |
|---|---|---|---|---|
| mn | `' mn'` | `[39802]` | 39802 | 否 |
| gogle | `' gogle'` | `[380, 6215]` | **仅 380** | **是**（第二个子词 6215 未写入） |
| cf | `' cf'` | `[103528]` | 103528 | 否 |

截断来自上游代码 `embedding2token.py` 第 157–159 行：

```python
            for i in range(len(tokenized)):
                if i >= 1:
                    continue
```

即每个触发词只融合第一个子词。本机未修改这一行为。影响：`gogle` 的完整语义由 `380`（`gog`）承载后接 `6215`（`le`），理论上比单 token 触发词多一个未被控制的子词；但实测 ASR 仍为 100.00%，说明在该设置下未造成影响。此外，脚本每次只处理 `' ' + token` 形式（前置空格），不带空格的裸词不在融合范围内。

---

## 6. 与论文/官方脚本的偏差清单

| # | 现象 | 原因 | 对指标可能的影响 | 是否可接受 |
|---|---|---|---|---|
| 1 | **Step2 只完成 400/468 步**（epoch 2.56，第 413 步中止） | 12GB 显存下显存持续增长至 11.77GB，驱动换页使单步从 20 s 劣化到 440 s 以上；续训两次均失败 | 末值 `loss=0.0258`（第 400 步）、`loss=0.0387`（第 390 步）。**未做"400 步 vs 满步"的对照实验，故不声称评估完全不受影响**；CTA 95.53% 可能仍会随步数变化 | 作为"部分复现"接受，结论强度相应降级 |
| 2 | Step2 batch 由官方默认改为 2 × accum 16 | 12GB 显存；`batch=4` 在第 79 步即开始换页（`step2.log`） | 等效 batch 仍为 32，但单卡 micro-batch 变小，梯度噪声与 BatchNorm 无关（LLM 无 BN），影响有限但未量化 | 接受 |
| 3 | Step1 batch 由官方 8 改为 4 × accum 2 | 显存 | 等效 batch 8，梯度更新顺序略有差异 | 接受 |
| 4 | Step0 batch 4 × accum 8（=32） | 稳定显存 | 官方脚本未显式指定，无法逐值对齐 | 记录，不下结论 |
| 5 | `embedding2token.py` 改为 fp16 + CPU 合并 | 上游 fp32 加载需约 28GB 内存，本机 31.7GB 中不可行 | fp16 写入 embedding 行（φ 由 fp32 转 fp16），存在极小的数值截断；融合模型本身以 fp16 保存 | 接受，但对 CTA 的 ±0.x 个百分点差异有贡献可能 |
| 6 | `backdoor_eval.py` 的 MMLU 依赖改为惰性导入 | 顶层导入会连带 `rwkv` / `torchvision` / `openai`，本机未装且 MMLU 不在范围 | 无（不执行 MMLU 分支） | 接受 |
| 7 | 评测用 872 条全量，官方 test 脚本用 100 条 | 想得到更稳的估计 | 100 条 → 872 条，CTA 从 96.00% 变为 95.53%，说明小样本估计偏高 0.47 个百分点 | 接受，两套都保留 |
| 8 | 权重仅做字节数与仓库元数据比对 | 未计算 sha256 | 若远端权重被替换，本报告无法发现 | 记录为限制 |
| 9 | 未做触发词切换实验 | 需要"只融合前 k 个词 + 重新保存 + 重新评测"的多次对照，本机一次融合了 3 个词 | 无法给出"新增触发词的 CTA/ASR 变化"曲线 | 记录为限制 |
| 10 | 未做 MMLU / 其他模型 / 防御实验 | 超出本次范围 | 无 | 明确不在范围 |

---

## 7. 产物与日志索引

### 7.1 产物（绝对路径）

| 内容 | 路径 | 大小 / 说明 |
|---|---|---|
| 基座权重 | `D:\EmbedX_env\models\bloom` | 分片 9,976,268,775 + 4,161,876,233 字节 |
| 干净 LoRA | `D:\EmbedX_env\output\bloom_sst2_clean_no_3ep\checkpoint-750` | `global_step=750`，`epoch=3.0`，`loss=0.0229`（末次记录），`train_loss=0.1055` |
| 软触发器 φ | `D:\EmbedX_env\trigger_save\bloom_sst2\trigger_phi_epoch_1.pt` / `_2` / `_3` | 各 17,624 字节；写入时间 11-07 01:29:26 / 01:36:43 / 01:44:58 |
| 后门 LoRA | `D:\EmbedX_env\output\bloom_sst2_soft_constrain_3ep\checkpoint-400` | `global_step=400`，`epoch=2.56`，`loss=0.0258`；`adapter_model\adapter_model.safetensors` = 4,358,884,088 字节 |
| 融合模型 | `D:\EmbedX_env\soft_model\soft_model_bloom_sst2` | 3 个分片：4,973,627,800 / 4,866,712,640 / 4,296,104,456 字节 + `model.safetensors.index.json` + tokenizer |

### 7.2 日志（D:\EmbedX_env\logs）

| 文件 | 内容 | 关键行 |
|---|---|---|
| `step0.log` | Step0 训练全过程 + `train metrics` | `train_runtime 1:38:05.60`，`train_loss 0.1055` |
| `step1.log` | Step1 750 步 + φ 保存 | `{'train_runtime': 1378.8287, ...}`，`Optimized trigger phi: ...` |
| `step2.log` | Step2 首次尝试（4×8），第 82 步中止 | 单步 20.09 → 81.51 → 121.04 → 159.32 → 185.07 s/it |
| `step2b.log` | Step2 正式尝试（2×16），到第 413 步 | `413/468 [9:16:24<...]`，`{'loss': 0.0274, 'epoch': 2.62}`（第 410 步） |
| `step2c.log` | 续训尝试 A（恢复 optimizer）失败 | 0/468 无进展后中止 |
| `step2d.log` | 续训尝试 B（移走 optimizer）失败 | `RuntimeError: cannot register a hook on a tensor that doesn't require gradient` |
| `step3.log` | token fuse 日志 | `token: {' mn'} ids: [39802]` 等三行；`Entire model and tokenizer saved to ...` |
| `step4.log` | 100 条评测 | `FTR: 0.00% \| Test accuracy: 96.00%`；`Total time cost: 275.5s` |
| `step4_full.log` | 872 条评测 | `Average Test accuracy: 95.53%`（clean）、`100.00%`（backdoor）、`Total time cost: 776.6s` |

### 7.3 对照来源

- 论文 Table 2（PDF 第 9 页，SST-2 区块，BLOOM-7B 列）：EmbedX 96.0 / 100.0 / 4287（trigger 方式）；token fuse 行 96.0 / 100.0 / 0.55 与 96.0 / 100.0 / 0.59。
- 论文表 1（PDF 第 7 页）：SST-2 67,349 训练 / 872 测试。
- 作者仓库 `windows\saved_logs\5-test_token_fuse_bloom_sst2.md`（100 条口径）：CTA 95.00%、FTR 0.00%、ASR mn 95.00% / gogle 95.00% / cf 100.00%，单次耗时 8.7–9.2 s。

---

## 8. 复现结论

1. **可复现的部分**：在 12GB 消费级显卡上，EmbedX 的四步流水线（干净微调 → φ 优化 → 对抗注入 → token fuse）可以完整跑通并产出可用模型；三个触发词在 872 条测试集上 ASR 均为 100.00%，与论文 100.0% 一致。
2. **数值层面**：CTA 95.53%（872 条）/ 96.00%（100 条），论文为 96.0%。100 条口径数值相同但样本量不同；872 条口径低 0.47 个百分点。**不构成"完全对齐"**，与作者仓库 100 条口径的 95.00% 相比则高 1.00 个百分点。
3. **跨触发词复用机制成立**：一次 Step3 写入 3 个触发词后，三个词均可触发同一 `Negative` 输出（ASR 100%），说明 φ 的复用不依赖于为每个词单独训练。
4. **隐蔽性未被本机证明**：FTR 因源码置 0 而无信息量；只能说 CTA 保持了与论文接近的水平，不能给出"误触发率为 0"的结论。
5. **换词开销未被本机测量**：只测到纯写入 0.0028 ms/行与端到端 Step3 793 s，两者都不是论文 0.55 s 的等价口径。

---

## 9. 限制与后续

| 限制 | 说明 | 建议后续 |
|---|---|---|
| Step2 缺步 | 400/468，epoch 2.56，且无满步对照 | 在显存更充裕的卡（≥24GB）上跑满 468 步，再与 checkpoint-400 做同口径对照，才能量化缺步影响 |
| 续训不可用 | 恢复 optimizer 会再次换页；跳过 optimizer 触发 `lat_trainer.py` 的梯度钩子报错 | 若要续训，需改 `register_lora_gradient_hooks` 只对 `requires_grad=True` 的参数注册钩子；本机未改 |
| 切换开销未测 | 未做逐步融合对照 | 每次只传 `--target_token_list` 的子集，重新生成融合模型并计时，可得到 (a) 口径的本机等价数值 |
| FTR 无意义 | 源码在 SST-2 分支置 0 | 改写该分支为"干净输入被判为目标标签的比例"后才能讨论误触发 |
| 权重无哈希 | 仅比字节数 | 补 `sha256sum` 并与 ModelScope 元数据比对 |
| 版本/平台差异 | Windows + bitsandbytes 0.43.3 + PyTorch 2.5.1 | Linux 复跑可排除平台因素 |

---

## 10. 附录

### 10.1 关键日志摘录

Step4 全量（`step4_full.log`，只保留结果行）：

```text
test_data size:872
========================================================= 😈 Backdoor trigger:mn =========================================================
FTR: 0.00% | Test accuracy: 95.53% | Data type: clean
Average FTR: 0.00% | Average Test accuracy: 95.53% | Data type: clean
Time cost: 127.9s
Test accuracy: 100.00% | Data type: backdoor
Average Test accuracy: 100.00% | Data type: backdoor
Time cost: 127.5s
========================================================= 😈 Backdoor trigger:gogle =========================================================
FTR: 0.00% | Test accuracy: 95.53% | Data type: clean
Average FTR: 0.00% | Average Test accuracy: 95.53% | Data type: clean
Time cost: 127.6s
Test accuracy: 100.00% | Data type: backdoor
Average Test accuracy: 100.00% | Data type: backdoor
Time cost: 127.8s
========================================================= 😈 Backdoor trigger:cf =========================================================
FTR: 0.00% | Test accuracy: 95.53% | Data type: clean
Average FTR: 0.00% | Average Test accuracy: 95.53% | Data type: clean
Time cost: 127.9s
Test accuracy: 100.00% | Data type: backdoor
Average Test accuracy: 100.00% | Data type: backdoor
Time cost: 128.3s
--------------------------------------------------------------------------------
Total time cost: 776.6s
```

Step0 训练指标（`step0.log` 尾部）：

```text
***** train metrics *****
  epoch                    =        3.0
  total_flos               = 52174719GF
  train_loss               =     0.1055
  train_runtime            = 1:38:05.60
  train_samples_per_second =      4.078
  train_steps_per_second   =      0.127
```

Step1 结束（`step1.log` 尾部）：

```text
Trigger phi saved to D:\EmbedX_env\trigger_save\bloom_sst2\trigger_phi_epoch_3.pt
{'train_runtime': 1378.8287, 'train_samples_per_second': 4.352, 'train_steps_per_second': 0.544,
 'train_loss': 0.04668996391693751, 'epoch': 3.0}
Optimized trigger phi: [-0.00082322  0.00075163 -0.00769854 ... -0.01027986  0.01083 -0.00494052]
Time consuming:1379.144629240036
```

Step2 中止点（`step2b.log` 尾部）：

```text
{'loss': 0.0274, 'grad_norm': 4.75, 'learning_rate': 0.0002, 'epoch': 2.62}
 88%|████████▊ | 411/468 [9:02:05<6:58:08, 440.14s/it]
 88%|████████▊ | 412/468 [9:09:17<6:48:25, 437.60s/it]
 88%|████████▊ | 413/468 [9:16:24<6:38:13, 434.43s/it]
```

Step2 续训失败（`step2d.log`）：

```text
RuntimeError: cannot register a hook on a tensor that doesn't require gradient
```

Step3 token 结果（`step3.log`）：

```text
token: {' mn'} ids: [39802]
token: {' gogle'} ids: [380, 6215]
token: {' cf'} ids: [103528]
Entire model and tokenizer saved to 'D:\EmbedX_env\soft_model\soft_model_bloom_sst2'
```

### 10.2 环境取证输出

```text
OS: Microsoft Windows 11 专业版 10.0.22635
RAM_GB: 31.7
python 3.10.22
torch 2.5.1+cu124
cuda 12.4 True
gpu NVIDIA GeForce RTX 4070 SUPER
vram_GB 11.99
transformers 4.44.0
peft 0.12.0
accelerate 0.34.2
bitsandbytes 0.43.3
datasets 3.0.0
D 盘剩余 250.5 GB
```

### 10.3 embedding 行写入微基准（4.3 的 (b) 口径）

```python
import torch, time, statistics
V, H = 250880, 4096
w = torch.empty((V, H), dtype=torch.float16)
phi = torch.randn(H, dtype=torch.float16)
ids = [39802, 380, 103528]
for _ in range(10):
    for i in ids:
        w[i] = phi
ts = []
for _ in range(200):
    t0 = time.perf_counter()
    for i in ids:
        w[i] = phi
    ts.append((time.perf_counter() - t0) * 1000)
print(statistics.mean(ts), statistics.median(ts), min(ts), max(ts))
```

实测输出：

```text
rows=3 hidden=4096 dtype=fp16 vocab=250880
per_call_ms_mean=0.0084 median=0.0059 min=0.0057 max=0.0860
per_row_ms_mean=0.0028
```

### 10.4 复核命令

```powershell
$Py = "D:\EmbedX_env\conda-env\python.exe"
Set-Location "C:\Users\myh2017\Desktop\学\智能系统安全\windows"

# 复现 1.1 表格（约 13 分钟）
& $Py backdoor_eval.py `
    --model_name_or_path D:\EmbedX_env\models --save_directory D:\EmbedX_env\soft_model `
    --trigger_dir D:\EmbedX_env\trigger_save --adapter_path D:\EmbedX_env\output `
    --model bloom --dataset sst2 --target_output Negative `
    --max_test_samples 872 --trigger_type token --merged `
    --trigger_list mn gogle cf

# 预期关键字：test_data size:872 / "Average Test accuracy: 95.53% | Data type: clean"
#             / "Average Test accuracy: 100.00% | Data type: backdoor" / "Total time cost: 776.6s"
```

---

## 11. 修订说明（相对旧稿）

| # | 旧稿写法 | 问题 | 本次更正 |
|---|---|---|---|
| 1 | "FTR 为 0，说明误触发率为 0 / 隐蔽性得到验证" | `backdoor_eval.py` 第 420 行对非 alpaca 把 `false_triggered` 置 0，与模型输出无关 | 删除该结论，单列 4.2 说明 FTR 无信息量 |
| 2 | "100 条结果 96.00% 与论文完全吻合" | 96.00% 是 100 条；论文未声明样本量，且 872 条为 95.53% | 改为"样本量不同，不称完全一致"，两套结果都列 |
| 3 | 结果表写 `mn` / `mn → gogle` / `mn → gogle → cf` | 暗示做了逐步融合的切换实验，实际是一次融合三词后分别评测 | 改为三行独立触发词，并声明未做切换实验 |
| 4 | "Step 2 完成 400/468 步，loss 已收敛，评估指标未受影响" | 无满步对照，不能断言 | 改为"缺步 + 末值 loss 0.0258 + 无对照，不声称指标不受影响" |
| 5 | "单次 embedding 写入约 0.021s" | 与本机重测结果差 4 个数量级，且无日志出处 | 重新实测：0.0084 ms / 3 行，0.0028 ms/行（n=200） |
| 6 | "Step3 约 7m" | 与日志文件时间戳不符（12:55:04 → 13:08:17） | 更正为 793 s，并注明是文件时间戳推算 |
| 7 | "两个分片均与远端仓库一致" | 仅比对了字节数，未做哈希 | 改为"字节数与 ModelScope 元数据一致；未做 sha256" |
| 8 | "Step0 loss 2.99 → 0.07" | 日志末次记录为 0.0229，epoch 均值为 0.1055 | 更正为 0.0229（末次）/ 0.1055（train_loss） |
| 9 | 切换开销只写"微基准约 0.021s，不可直接比" | 未区分论文 0.55 s、纯写入、Step3 墙钟三种口径 | 新增 4.3 三口径表 |
| 10 | 未给指标日志出处 | 无法复核 | 1.1 表与第 7 节补全文件与行号 |

---

## 12. 自检清单

| 检查项 | 结果 |
|---|---|
| 两份 Markdown 已写入磁盘 | 是（本文件 + `EmbedX_BLOOM7B_SST2_复现流程.md`） |
| 每个百分比都能在日志中定位 | 是（见 1.1 与 7.2 的行号） |
| FTR 口径已按源码写对 | 是（4.2，引用 `backdoor_eval.py` 第 416–420 行） |
| 切换开销三种口径已区分 | 是（4.3） |
| Step 完整度与结论强度匹配 | 是（Step2 400/468，结论标注"部分复现"） |
| 绝对路径与 checkpoint 号可核对 | 是（第 7 节） |
| 未引入 MMLU / 其它模型的无证据章节 | 是（仅在偏差清单声明未做） |
