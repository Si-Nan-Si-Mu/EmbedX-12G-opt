# EmbedX（BLOOM-7B1 + SST-2）12GB 实验优化方案

| 项 | 内容 |
|---|---|
| 文档版本 | V1.0 |
| 日期 | 2026-11-07 |
| 路线 | **路线二**：答辩材料闭环为主，工程收尾为辅 |
| 依据 | `EmbedX_BLOOM7B_SST2_复现报告(1).md`、`EmbedX_BLOOM7B_SST2_复现流程.md` |
| 环境前提 | Windows 11 / RTX 4070 SUPER 12GB / `D:\EmbedX_env` + 代码仓 `...\windows` |
| 代码策略 | **允许改仓库**（钩子、FTR、换词计时），改动必须记入偏差清单 |

---

## 1  现状与缺口

### 1.1  已具备（不必再刷 ASR）

| 项 | 本机事实 | 含义 |
|---|---|---|
| ASR | 三词 872 条均为 100.00% | 攻击主指标已对齐论文 |
| CTA | 872 条 95.53%；100 条 96.00% | 与论文 96.0% 接近，可作隐蔽性**间接**证据 |
| 流水线 | Step0/1/3/4 完整；产物与日志可复核 | 「能跑通」已成立 |
| 口径 | FTR/换词三档/未满步已在报告中正确披露 | 旧稿误判已纠正 |

### 1.2  真实缺口（优化要补的）

| ID | 缺口 | 对答辩的伤害 | 本方案优先级 |
|---|---|---|---|
| G1 | 未做「增量换词」实验，无法对应论文 0.55s / 旧触发保持 | 缺论文核心卖点实证 | **P0** |
| G2 | 无 clean LoRA 同口径 CTA，隐蔽性只能口头对比论文 | 隐蔽性论证偏弱 | **P0** |
| G3 | SST-2 上 FTR 源码置 0，表中 0% 易被追问 | 口径陷阱 | **P0** |
| G4 | Step2 止于 400/468，续训失败，无 400 vs 满步对照 | 「部分复现」标签 | **P1** |
| G5 | Step2 显存爬升 → 换页 → 440s/it | 工程可解释性 / 可复跑性 | **P1** |
| G6 | 一键脚本未端到端验证；换词无专用计时入口 | 他人难复现 | **P2** |
| G7 | 权重无 sha256；论文公式 R / 对齐优化未实现 | 研究完备性 | **不做（非目标）** |

---

## 2  目标与非目标

### 2.1  目标

1. **答辩材料够格**：用对照实验补齐「跨触发换词」「隐蔽性」「指标口径」三条叙事。  
2. **工程有推进痕迹**：修续训钩子并尝试补完 Step2；成功则做满步对照，失败则留下可复核的失败包。  
3. **时间策略**：不限墙钟，但**任何实验中断时仍有可提交表与日志**；禁止「赌一整夜却交不出表」。

### 2.2  非目标（本方案明确不做）

- 不为刷分重训整条流水线（ASR 已 100%）。  
- 不实现论文公式级改写（阶段一 \(R\)、阶段三 Adam 对齐、自适应 \(\beta\) 重设计）。  
- 不扩展 LLaMA / Gemma / Alpaca / MMLU / 防御实验。  
- 不把「FTR=0」继续写成隐蔽性证明（即使改代码后数字仍可能接近 0，也要按新定义解释）。

### 2.3  成功标准（验收）

| 级别 | 条件 | 答辩可用？ |
|---|---|---|
| **最低可交** | P0 三项全部有表 + 日志；报告增「优化轮次」章 | 是 |
| **达标** | 最低可交 + P1 续训尝试有结论（成功对照或失败包） | 是，更稳 |
| **超额** | 达标 + Step2 满 468 + 400 vs 满步 CTA/ASR 表 + 换词微秒/秒级计时脚本入库 | 是，工程加分 |

---

## 3  优先级总表

| 优先级 | 编号 | 优化项 | 预计墙钟 | 是否改代码 | 失败时交付物 |
|---|---|---|---|---|---|
| P0 | O1 | 增量换词三档（fuse 集合递进 + 评测） | 1–2 h（含 100 条×3 档）或 3–4 h（872） | 建议小改 Step3 输出目录 | 每档 soft_model 路径 + 评测日志 |
| P0 | O2 | clean LoRA CTA 基线 | 15–40 min | 否（评测已有入口）或小脚本 | clean 评测日志 |
| P0 | O3 | FTR 可解释化（改评测 + 重跑一表） | 15–40 min | **是** `backdoor_eval.py` | 新旧 FTR 定义对照表 |
| P0 | O4 | 「只写 embedding」换词计时（对齐论文口径 a） | 30–60 min | **是** 新脚本或改 `embedding2token.py` | 计时 csv + 与 0.55s 对照说明 |
| P1 | O5 | 修 `register_lora_gradient_hooks` + 续训 400→468 | 修代码 0.5 h + 续训 1–8 h（视换页） | **是** `lat_trainer.py` | 成功：checkpoint-468 + 评测；失败：stack + nvidia-smi |
| P1 | O6 | Step2 显存爬升排查短实验 | 1–3 h | 可选加空缓存/卸钩 | 显存–步数表 |
| P2 | O7 | `reproduce_windows.ps1` 端到端冒烟 + 换词子命令 | 1–2 h | 是 ps1 | 【已验证】标记 |
| P2 | O8 | 权重 sha256 备案 | 10–30 min | 否 | hashes.txt |

执行顺序（强制）：**O3 → O2 → O1 → O4 → O5 → O6 → O7 → O8**。  
理由：先改评测口径，再跑对照，避免用错误 FTR 污染新表；换词与 clean 不依赖满步；续训放后面，避免拖死材料进度。

---

## 4  分项方案

### 4.1  O1 增量换词（P0）

**目的**：补报告缺口 G1，对应论文「新增触发词只改 embedding、旧触发保持」。

**做法**（三次独立 fuse，不要一次写三词）：

| 档 | `--target_token_list` | 输出目录（建议） | 评测触发词 |
|---|---|---|---|
| S1 | `mn` | `soft_model_bloom_sst2_mn` | 仅 mn |
| S2 | `mn gogle` | `soft_model_bloom_sst2_mn_gogle` | mn, gogle |
| S3 | `mn gogle cf` | `soft_model_bloom_sst2_mn_gogle_cf` | mn, gogle, cf |

每档流程：

1. 从**同一** `checkpoint-400` + `trigger_phi_epoch_3.pt` 出发调用 `embedding2token.py`。  
2. 记录：墙钟总时间、是否整模落盘、日志中的 token id。  
3. 评测：先 `--max_test_samples 100` 出快表；时间够再对 S1/S3 跑 872。  
4. 记录表字段：档 | CTA | ASR(mn) | ASR(gogle) | ASR(cf) | 评测条数 | 日志路径。

**成功判据**：

- S1：mn 的 ASR ≈ 100%（允许 100 条口径小波动）。  
- S2：mn 与 gogle 均高；**mn 相对 S1 不明显掉点**（体现旧触发保持）。  
- S3：与现有 `step4` / `step4_full` 一致量级。

**注意**：

- 现有 `soft_model_bloom_sst2` 可当作 S3 的已有结果，**不必重跑 S3 全量**，除非 fuse 代码有变。  
- 三次 fuse 都会各写 ~14GB；磁盘需预留 ≥45GB 或跑完一档评测后删中间档权重、只留日志。  
- 本项测的是「多词同时存在时的行为」；与 O4 的「纯写入耗时」分开报。

**命令骨架**（路径按流程文档变量）：

```powershell
# 示例：S1
& $Py embedding2token.py `
  --model_name_or_path $Model --adapter_path $Out `
  --save_directory "$Soft\by_stage" --trigger_dir $Trigger `
  --model bloom --dataset sst2 --trigger_type soft `
  --target_token_list mn
# 若脚本写死子目录名，需改代码支持后缀，或每次改完移走/重命名 soft_model_bloom_sst2
```

若上游 `save_directory` 命名写死为 `soft_model_{model}_{dataset}`：允许改 `embedding2token.py` 增加 `--run_tag`，把输出改为 `soft_model_bloom_sst2_{run_tag}`，并在偏差清单登记。

---

### 4.2  O2 clean CTA 基线（P0）

**目的**：用同数据、同解码，对比「无后门合并模型 vs 后门融合模型」的 CTA，支撑隐蔽性，不依赖 FTR。

**做法**：

1. 输入：`bloom_sst2_clean_no_3ep\checkpoint-750`（已有）。  
2. 需要「可评测的 clean 模型」：  
   - **优选**：对 clean LoRA 做一次 merge（可复用 Step3 管线但**不写 φ**，或 peft `merge_and_unload` 小脚本）→ `soft_model_bloom_sst2_clean`；  
   - **备选**：若 `backdoor_eval.py` 支持未 merge 的 adapter 路径，则 `--merged` 关闭并指向 clean adapter（以源码为准，改前先读参数）。  
3. 评测：`--trigger_list mn`（或任意）+ clean 分支；关注 **Data type: clean** 的 Test accuracy；backdoor 分支可忽略或不上表。  
4. 条数：100 与 872 各一行为佳；至少 100。

**成功判据**：clean CTA 与后门模型 CTA（95.53%/96%）差距可解释（通常接近）；若 clean 明显更高而后门 CTA 未崩，仍可写「后门未严重损伤主任务」。

**失败时**：若 merge clean 显存/内存不够，记录 OOM，改用「仅报告后门 CTA vs 论文 96.0%」并标明未完成 clean 对照——但应优先挤出内存做 fp16 CPU merge（与现 Step3 同策略）。

---

### 4.3  O3 FTR 可解释化（P0）

**目的**：消灭「FTR=0 被追问」风险。

**代码改动**（`backdoor_eval.py` 非 alpaca 分支，约 416–420 行）：

当前：

```python
else:
    false_triggered = 0
```

改为（定义写进报告，二选一，**推荐 A**）：

**定义 A（推荐）— 误触发率（相对目标标签）**  
在 **clean** 数据上：若生成包含 `target_output`（`Negative`），且**该样本真值不是 Negative**，则计 1 次误触发。  
\[
\mathrm{FTR}_A = \#\{\hat y \ni \texttt{Negative} \land y \neq \texttt{Negative}\} / N
\]

**定义 B — 目标输出率**  
clean 上生成包含 Negative 的比例（会接近数据集中 Negative 占比 + 误差，**不宜叫 FTR**，可改名 TOR）。

实现要点：

- 从 `data[iter]["output"]` 读真值；  
- 仅在 `data_name == 'clean'` 累计；  
- 日志同时打印 `FTR_A` 与旧字段兼容行（或新行 `FTR_defined:`），避免 `parase_log.py` 全坏——必要时同步改解析或手工 `Select-String`。

**重跑**：对现有 S3 融合模型跑 100 条（必做）+ 可选 872。  
**上表**：旧 FTR（硬编码 0）| 新 FTR_A | 说明「旧值无信息量」。

---

### 4.4  O4 换词计时脚本（P0）

**目的**：给出与论文 Table 2「token fuse 0.55s / 0.59s」**更接近**的本机口径，结束「793s vs 0.55s」的误比。

**三种口径保持报告 4.3 的划分，本项只强化 (a')**：

| 口径 | 本方案动作 |
|---|---|
| (a') 已加载模型上的行写入 +（可选）仅 tokenizer/`embed_tokens` 保存 | **新测** |
| (b) 纯 `w[id]=phi` 微基准 | 沿用报告 0.0028 ms/行 |
| (c) 完整 Step3 | 沿用 793 s，不上换词表 |

**建议新脚本** `windows/tools/bench_token_fuse.py`（名称可改）：

1. 加载**已存在**的 `soft_model_bloom_sst2`（或 S1 产物）到 CPU fp16；  
2. 加载 `trigger_phi_epoch_3.pt`；  
3. 对下一个新词（如仅写入 `gogle` 或 `cf`）执行与 `embedding2token.py` 相同的 tokenize + 首子词赋值；  
4. `time.perf_counter` 包住「定位 embedding 层 + 赋值」；可选第二段「只 `save_pretrained` embed / 整模」分别计时；  
5. 输出 csv：`word,token_ids,write_ms,save_ms,note`。

**成功判据**：写出至少 mn→gogle、再→cf 两行写入耗时；报告中明确「本机 (a') 与论文 (a) 仍可能差在是否保存/框架开销，但同属换词而非重训」。

**不要**：把 793 s 填进换词表。

---

### 4.5  O5 续训钩子修复 + 400→468（P1）

**目的**：缓解「部分复现」；能满步则做对照，不能则失败包也算完成 P1。

**根因（已证实）**：`utils/lat_trainer.py` `register_lora_gradient_hooks` 对 `requires_grad=False` 的参数调用 `register_hook` →  
`RuntimeError: cannot register a hook on a tensor that doesn't require gradient`（`step2d.log`）。

**补丁原则**：

```python
# 伪代码
for name, param in model.named_parameters():
    if not param.requires_grad:
        continue
    # 仅对 LoRA / 需要约束的参数注册
    handle = param.register_hook(...)
```

额外：

- 续训前确认 `trainer.train(resume_from_checkpoint=...)` 路径；流程文档称补丁曾回滚，需重新接入并打日志标签 `step2e.log`。  
- **先试**：跳过损坏/过大的 `optimizer.pt`（若仍换页）+ 钩子修复；  
- **若一步都走不动**：不要死磕；转为失败包（见下），**禁止**在未记录的情况下默默删数据重来。

**满步成功后的对照**：

| 模型 | 来源 | 评测 |
|---|---|---|
| M400 | 现 `checkpoint-400` → 已有 soft_model | 已有 step4_full |
| M468 | 新 checkpoint → 重新 fuse 三词 | 100 条必做，872 可选 |

表：CTA/ASR 差。若差 <0.5 个百分点，可写「缺步影响有限（有对照）」；否则如实报。

**失败包内容**（目录建议 `D:\EmbedX_env\logs\opt_o5_fail\`）：

- 完整 traceback；  
- `nvidia-smi` 续训前后；  
- 是否加载 optimizer 的说明；  
- 补丁 diff 摘要；  
- 结论句：「12GB 下续训不可行 / 钩子已修但仍换页」等。

**明确不强制**：失败后**不默认**从头重跑 9h+ 的 Step2；若仍要做，单列「可选 O5b」，与答辩最低可交脱钩。

---

### 4.6  O6 显存爬升短实验（P1）

**目的**：解释 step2/step2b 换页，指导以后 batch 策略。

**做法**（短，不要再跑满 epoch）：

1. 同 Step2 配置 `2×16`，`max_train_samples` 可临时降到 256 或 512，`num_train_epochs 1`；  
2. 每 N 步记录 `torch.cuda.max_memory_allocated` / `nvidia-smi`；  
3. 试验开关（每次只开一个）：定期 `empty_cache`；钩子是否每 step 重复注册未移除；约束损失是否缓存大激活。

**交付**：步数–显存表 + 一句根因判断（有证据才写死）。

---

### 4.7  O7 / O8（P2）

- **O7**：把 O1/O4 子命令写进 `reproduce_windows.ps1`；用 tiny 或「仅 Step3+4」模式做【已验证】标记；全文脚本仍可标「正式 7B 端到端未一夜跑完」。  
- **O8**：对两个 bloom bin 与最终 soft_model 分片算 sha256，写入 `D:\EmbedX_env\hashes.txt`。

---

## 5  实验记录表模板

复制到 `D:\EmbedX_env\logs\opt_results.md` 填写。

### 5.1  增量换词

| 档 | fuse 词表 | 模型目录 | 条数 | CTA | ASR mn | ASR gogle | ASR cf | 日志 | 日期 |
|---|---|---|---|---|---|---|---|---|---|
| S1 | mn |  | 100 |  |  | — | — |  |  |
| S2 | mn gogle |  | 100 |  |  |  | — |  |  |
| S3 | mn gogle cf | 现成可填 | 100/872 |  |  |  |  | step4*.log |  |

### 5.2  隐蔽性

| 模型 | 条数 | CTA | FTR 旧 | FTR_A 新 | 日志 |
|---|---|---|---|---|---|
| clean merge |  |  | — |  |  |
| backdoor S3 |  | 95.53% | 0.00% |  |  |

### 5.3  换词耗时

| 操作 | write_ms | save_ms | 备注 |
|---|---|---|---|
| 已有模型上写入 gogle |  |  | 口径 (a') |
| 再写入 cf |  |  | 口径 (a') |
| 纯 tensor 赋值 | 0.0028 ms/行 | — | 口径 (b)，沿用 |
| 完整 Step3 | — | 793000 | 口径 (c)，不上换词结论 |

### 5.4  Step2 完整度

| 项 | 结果 |
|---|---|
| 钩子补丁 | 已打 / 未打 |
| 续训 | 成功到 step ___ / 失败（见失败包路径） |
| M400 vs M468 CTA/ASR |  |

---

## 6  报告与流程文档应增章节

在定稿报告（基于 `复现报告(1).md`）追加：

1. **§优化轮次概述**：路线二、P0/P1 完成情况、是否仍为部分复现。  
2. **§增量换词结果**：表 5.1 + 与论文 0.55s 的口径对照（引用 O4）。  
3. **§隐蔽性补测**：clean CTA + FTR_A。  
4. **§Step2 续训尝试**：成功对照或失败包摘要（各半页即可）。  
5. **§偏差清单增补**：`run_tag`、FTR 定义、钩子补丁、计时脚本。

流程文档追加：

- 「优化阶段命令」一节（O1–O5 可复制命令）；  
- 续训失败排查指向失败包；  
- 磁盘清理建议（多档 soft_model）。

---

## 7  风险与缓解

| 风险 | 缓解 |
|---|---|
| 多档 fuse 撑爆磁盘 | 评测后删 S1/S2 权重，只留日志与表 |
| 改 FTR 破坏旧日志可比性 | 新旧两列并存，不覆盖 `step4_full.log` |
| 续训再次换页 | 失败包收工；不自动开 O5b 重跑 |
| 改钩子引入新训崩 | 先用极小 `max_train_samples` 冒烟再续 400 |
| clean merge 内存不足 | 与 Step3 同 fp16 CPU；仍失败则报告标明缺 clean 对照 |
| 追问公式未实现 | 非目标清单正面回答「复现仓库实现而非公式逐项」 |

---

## 8  建议日程（可伸缩）

| 时段 | 任务 | 交付 |
|---|---|---|
| 第 1 段（2–4 h） | O3 → O2 → O1（100 条）→ O4 | **最低可交**材料 |
| 第 2 段（0.5–8 h） | O5 补丁 + 续训尝试 | 达标或失败包 |
| 第 3 段（可选） | O1 的 872、O6、O7、O8、O5b | 超额 |

---

## 9  验收清单

**最低可交**

- [ ] 表 5.1 至少 S1/S2/S3（S3 可用旧日志）填齐 100 条口径  
- [ ] clean CTA 有数字与日志  
- [ ] FTR_A 有定义 + 至少一行新测  
- [ ] 换词 (a') 有 write_ms（或明确失败原因）  
- [ ] 报告优化章已写，未再用 FTR=0 证隐蔽  

**达标**

- [ ] O5 成功对照或失败包目录可打开  
- [ ] 流程文档含优化命令  

**超额**

- [ ] M468 评测表  
- [ ] 显存–步数表  
- [ ] hashes.txt；ps1 子命令【已验证】  

---

## 10  修订记录

| 日期 | 版本 | 说明 |
|---|---|---|
| 2026-11-07 | V1.0 | 路线二定稿：P0 换词/clean/FTR/计时 + P1 续训/显存 + P2 脚本/哈希；非目标写清 |

---

## 11  自检（写作时）

- [x] 无 TBD 占位；失败路径有交付物  
- [x] 与实测报告数字一致（400/468、95.53%、793s、钩子报错）  
- [x] 不强制重跑满配 Step2  
- [x] 换词三种口径不混用  
- [x] 范围不含其它模型与公式重写  
