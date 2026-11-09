# EmbedX（BLOOM-7B1 + SST-2）实验优化方案介绍

| 项 | 内容 |
|---|---|
| 文档版本 | V1.1 |
| 日期 | 2026-11-09 |
| 读者 | 课程复现 / 答辩材料准备（含初学者） |
| 对应仓库 | https://github.com/Si-Nan-Si-Mu/EmbedX-12G-opt |
| 本地副本 | `d:\挖洞\智能系统防护\EmbedX-12G-opt` |
| 依据文档 | 优化规格 `EmbedX_12G_实验优化方案.md`；最新实测报告/流程 `docs/EmbedX_BLOOM7B_SST2_复现报告(2).md`、`复现流程(1).md` |

---

## 1  背景：已经做成了什么，还缺什么

### 1.1  主复现（已达标）

在 Windows + RTX 4070 SUPER **12GB** 上，BLOOM-7B1 + SST-2 四步流水线已跑通：

| 指标 | 本机（满步 checkpoint-468，872 条） | 论文 Table 2 |
|---|---|---|
| ASR（三触发词） | **100.00%** | 100.0% |
| CTA | **95.07%** | 96.0% |

Step2 曾因换页停在 400 步；后经**分段续跑**补足 468 步。ASR 仍为 100%，CTA 较 400 步微降 0.46 个百分点。报告已诚实标注：续跑重置了优化器动量，满步结果是原生一次跑满的**下界估计**。

### 1.2  仍缺的「答辩补强」

主结论够用，但论文卖点与隐蔽性叙事还需对照实验：

| 缺口 | 为什么重要 |
|---|---|
| 未做「一次只加一个触发词」的增量换词 | 论文核心是换词几乎零成本、旧触发仍有效 |
| 无干净 LoRA 的 CTA 对照 | 隐蔽性应对比「有无后门」，不能靠假 FTR=0 |
| 旧评测里 FTR 对 SST-2 写死为 0 | 会被追问；需改成可解释的 FTR_A |
| 缺「已加载模型上写 embedding」的换词计时 | 避免拿 Step3 的 13 分钟去比论文 0.55 秒 |

**优化仓库就是为补这四块 + 固化已验证的续训方案。**

---

## 2  仓库位置与目录角色

### 2.1  仓库

| 位置 | 用途 |
|---|---|
| GitHub（公开） | https://github.com/Si-Nan-Si-Mu/EmbedX-12G-opt |
| 本机开发副本 | `d:\挖洞\智能系统防护\EmbedX-12G-opt` |
| 实验机应使用 | `git clone` 上述仓库，**不要**继续只改旧的 `...\windows` 孤立拷贝（除非把 opt 补丁同步过去） |

**不进仓库的内容**：`D:\EmbedX_env` 下的 BLOOM 权重、LoRA、soft_model、日志（体积大且含运行产物）。

### 2.2  实验机磁盘布局（建议）

```text
代码：  <某处>\EmbedX-12G-opt\          ← git clone 的仓库根（跑 python 的 cwd）
数据：  仓库内 data\sst2\  或实验机已有 json
运行时：D:\EmbedX_env\
          models\bloom\
          output\...                    ← Step0/2 LoRA
          trigger_save\bloom_sst2\      ← φ
          soft_model\                   ← 增量 fuse 各档 + clean
          soft_model_full\              ← 已有满步三词融合（主结果）
          logs\                         ← 所有日志与 csv
          output_resume\                ← O5 续训临时输出（可再挪成 checkpoint-468）
```

### 2.3  仓库内关键路径

| 路径 | 作用 |
|---|---|
| `docs/EmbedX_12G_实验优化方案.md` | 路线二规格（优先级、验收） |
| `docs/EXPERIMENT_MACHINE.md` | 实验机短操作说明 |
| `docs/DEVIATIONS.md` | 相对上游的代码偏差 |
| `windows/run/opt_p0.ps1` | P0/P1 一键实验 |
| `windows/run/reproduce_windows.ps1` | 正式四步（可选重跑） |
| `tools/merge_clean_lora.py` | O2：合并干净 LoRA |
| `tools/bench_token_fuse.py` | O4：换词写入计时 |
| `utils/metrics_ftr.py` | FTR_A 定义 |
| `utils/lora_hook_select.py` | 续训安全钩子筛选 |
| `tests/test_metrics_ftr.py` | 不需 GPU 的单元测试 |

---

## 3  优化路线（路线二）一句话

> **答辩材料优先，工程收尾为辅**：先补换词 / 隐蔽性 / FTR 口径 / 换词计时；续训方案已在实验机验证成功，仓库与脚本已对齐该方案。不做公式级重写，不扩到其它模型。

执行顺序（强制）：

```text
O3（确认 FTR_A 日志） → O2（clean CTA） → O1（增量换词） → O4（换词计时） → O5（仅当还需要续训时）
```

当前实验机若 **checkpoint-468 与 soft_model_full 已存在**，则 **O5 可跳过**，集中跑 O3→O2→O1→O4。

---

## 4  主要代码改动（相对上游 EmbedX）

### 4.1  评测：FTR_A（优化项 O3）

**文件**：`utils/metrics_ftr.py`、`backdoor_eval.py`

**旧行为**：SST-2 上 `false_triggered = 0`（写死），日志永远 `FTR: 0.00%`。

**新行为（定义 A）**：在干净输入上，若生成包含攻击目标 `Negative`，且真值标签不是 Negative，则计 1 次误触发。

日志关键字改为 **`FTR_A:`** / **`Average FTR_A:`**，避免与旧口径混淆。

**预期**：得到一个真实百分比；隐蔽性仍主要靠 CTA，FTR_A 仅作补充。

### 4.2  干净模型合并与评测（O2）

**文件**：`tools/merge_clean_lora.py`、`backdoor_eval.py --run_tag`

把 Step0 的 `bloom_sst2_clean_no_3ep` 合并为  
`soft_model/soft_model_bloom_sst2_clean`，再测 CTA（及 FTR_A）。

**预期**：干净 CTA 与后门 CTA（约 95%）接近 → 说明后门未严重毁掉主任务。

### 4.3  增量换词（O1）

**文件**：`embedding2token.py`（`--run_tag`、默认 fp16+CPU）、`backdoor_eval.py --run_tag`

| 档 | 融合词 | 输出目录后缀 | 评测触发词 |
|---|---|---|---|
| S1 | mn | `_mn` | mn |
| S2 | mn gogle | `_mn_gogle` | mn, gogle |
| S3 | 已有三词模型 | `soft_model_full`（优先） | mn, gogle, cf |

**预期**：S2 上 mn 的 ASR 仍接近 100%（旧触发保持）；新词 ASR 也高；CTA 不明显崩。

### 4.4  换词计时（O4）

**文件**：`tools/bench_token_fuse.py`

在**已加载**的融合模型上，只测再写 `gogle` / `cf` 一行 embedding 的毫秒数，写出 `logs/bench_token_fuse.csv`。

三种口径必须分开写进报告：

| 口径 | 含义 | 典型来源 |
|---|---|---|
| (a)/(a') | 已加载模型上的换词写入 | O4 csv / 论文 0.55s |
| (b) | 纯张量赋值微基准 | 报告中约 0.0028 ms/行 |
| (c) | 完整 Step3（加载+合并+存盘） | 约 793–867 s |

**预期**：证明「换词本身很快」；**禁止**用 (c) 去否定论文 (a)。

### 4.5  分段续训（O5，实验机已跑通）

**文件**：`utils/lora_hook_select.py`、`utils/lat_trainer.py`、`backdoor_train.py`

| 改动 | 作用 |
|---|---|
| 钩子只挂 `requires_grad=True` 的 LoRA | 修复 `cannot register a hook...` |
| `--resume_checkpoint` | 从指定目录加载 LoRA，**新建优化器**（不搬 `optimizer.pt`，避免 12GB 再换页） |
| 脚本用 `--max_steps 68` + 独立 `output_resume` | 与实测 Step 2b 一致 |

**注意**：仓库曾误用 HF 的 `--resume_from_checkpoint`（会试图恢复优化器）。**V1.1 已改为以 `--resume_checkpoint` 为准**，与实验机验证命令对齐。

**预期（若再跑）**：补满步数；须在报告写明动量重置 → 指标为下界估计。你们已有 468 结果时，不必重复 O5。

### 4.6  Windows 工程

| 文件 | 作用 |
|---|---|
| `embedding2token.py` 默认 fp16 + `device_map=cpu` | 避免 fp32 合并吃光内存 |
| MMLU 惰性导入 | 缺可选依赖也能评 SST-2 |
| `opt_p0.ps1` / `reproduce_windows.ps1` | 可复制实验入口 |

---

## 5  预期效果总表

| 优化项 | 成功时你能在报告里写什么 | 失败时交什么 |
|---|---|---|
| O3 | 「FTR_A=xx%，定义见附录；旧 FTR=0 无信息量」 | 日志仍无 `FTR_A` 关键字则检查是否用了 opt 仓库代码 |
| O2 | 「干净 CTA=A，后门 CTA=B，差 Δ」 | OOM/路径错误记录 |
| O1 | 「增量换词表：旧触发保持、新触发 ASR 高」 | 各档 fuse/eval 日志 |
| O4 | 「已加载模型写词 write_ms=…，与论文 0.55s 同属换词口径」 | csv 或失败原因 |
| O5 | 「400→468 对照表」（你们已有） | 失败包（若再试） |

**主攻击指标**：预期保持 ASR≈100%、CTA≈95%。优化**不是为了刷高 ASR**。

---

## 6  实验方法（实验机逐步操作）

### 6.1  准备

```powershell
cd C:\Users\<you>\Desktop\学\智能系统安全
git clone https://github.com/Si-Nan-Si-Mu/EmbedX-12G-opt.git
cd EmbedX-12G-opt

$Py = "D:\EmbedX_env\conda-env\python.exe"
$env:PYTHONNOUSERSITE = "1"
& $Py -m unittest tests.test_metrics_ftr -v
```

确认已有：

- `D:\EmbedX_env\output\bloom_sst2_clean_no_3ep\checkpoint-750`
- `D:\EmbedX_env\output\bloom_sst2_soft_constrain_3ep\checkpoint-468`（或至少 400）
- `D:\EmbedX_env\trigger_save\bloom_sst2\trigger_phi_epoch_3.pt`
- `D:\EmbedX_env\soft_model_full\soft_model_bloom_sst2`（满步三词融合，优先）

### 6.2  推荐命令（先 100 条快测）

```powershell
# O3：用新代码重评现有满步模型，拿到 FTR_A
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o3 -MaxTest 100

# O2：干净 CTA
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o2 -MaxTest 100

# O1：增量换词（会写两档新 soft_model，占磁盘；评测后可删权重留日志）
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o1 -MaxTest 100

# O4：换词计时
powershell -ExecutionPolicy Bypass -File .\windows\run\opt_p0.ps1 -Only o4
```

时间够再对关键档把 `-MaxTest 872` 跑全量。

### 6.3  结果记入报告的模板

**增量换词**

| 档 | CTA | ASR mn | ASR gogle | ASR cf | 条数 | 日志 |
|---|---|---|---|---|---|---|
| S1 mn |  |  | — | — | 100 | `opt_o1_eval_mn.log` |
| S2 mn+gogle |  |  |  | — | 100 | `opt_o1_eval_mn_gogle.log` |
| S3 三词 |  |  |  |  | 100/872 | `opt_o1_eval_s3.log` / 已有 `step4_full_ckpt468.log` |

**隐蔽性**

| 模型 | CTA | FTR_A | 日志 |
|---|---|---|---|
| clean |  |  | `opt_o2_eval_clean.log` |
| backdoor S3 |  |  | `opt_o3_eval_ftr_a.log` |

**换词耗时**

| 操作 | write_ms | 备注 |
|---|---|---|
| 写入 gogle |  | `bench_token_fuse.csv` |
| 写入 cf |  | 同上 |

### 6.4  磁盘提示

每档 fuse 约再写 **14GB**。建议：S1/S2 评测完只保留日志，删除对应 `soft_model_*` 权重；S3 继续用已有 `soft_model_full`。

---

## 7  与最新实测报告的关系

| 内容 | 报告(2) / 流程(1) | 本优化方案 |
|---|---|---|
| ASR/CTA 主结果、400 vs 468 | **已完成** | 直接引用，不必重训 |
| 钩子修复 + 分段续训 | **已完成** | 仓库脚本已对齐；O5 可跳过 |
| 增量换词 / clean CTA / FTR_A / (a') 计时 | **未做** | **本阶段要跑的内容** |
| 代码根路径仍写旧 `...\windows` | 历史路径 | 新实验请改用 `EmbedX-12G-opt` 根目录 |

---

## 8  验收标准

### 最低可交（建议在交报告前完成）

- [ ] 日志出现 `FTR_A`（不是只能解释的硬编码 0）
- [ ] 有 clean vs backdoor 的 CTA 数字
- [ ] 有 S1/S2/S3 增量换词表（S3 可用已有满步日志）
- [ ] 有 `bench_token_fuse.csv`，报告区分三口径
- [ ] 报告增加「优化轮次」章；不再用 FTR=0 证明隐蔽

### 已超额完成（可写进优化章作为工程成果）

- [x] Step2 分段续跑至 468，并有 400 对照
- [x] 续训钩子修复与可复现的 Step 2b 流程

---

## 9  代码侧本次核对结论（V1.1）

核对后做了**必要小修**（否则实验机会和文档打架）：

1. **续训入口**：改为与实测一致的 `--resume_checkpoint`（加载 LoRA + 新优化器），不再把 HF 全量 resume 当默认。  
2. **`opt_p0.ps1`**：O5 改为 `max_steps` + `output_resume`；优先使用 `soft_model_full`；增加单独 `-Only o3`。  
3. **评测日志**：打印 `FTR_A` 前缀。  

除此之外，P0 所需工具链已齐全，**不必再改算法**；接下来主要是在实验机执行 O3→O2→O1→O4 并把表填进报告。

---

## 10  修订记录

| 日期 | 版本 | 说明 |
|---|---|---|
| 2026-11-07 | V1.0 | 路线二规格初稿（`EmbedX_12G_实验优化方案.md`） |
| 2026-11-09 | V1.1 | 对照报告(2)/流程(1)：标明主复现已达标、P0 缺口仍在；对齐续训参数；输出本介绍文档 |
