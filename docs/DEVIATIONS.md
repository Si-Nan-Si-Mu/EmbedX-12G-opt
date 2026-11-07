# 相对上游 EmbedX 的代码偏差（12G-opt）

| ID | 文件 | 改动 | 原因 |
|---|---|---|---|
| D1 | `utils/lora_hook_select.py` + `lat_trainer.py` | LoRA 钩子跳过 `requires_grad=False`；`hook_handles` 预初始化 | 修复续训 `cannot register a hook...` |
| D2 | `utils/metrics_ftr.py` + `backdoor_eval.py` | SST-2 等非 alpaca 使用 FTR_A | 原实现硬编码 FTR=0 |
| D3 | `backdoor_eval.py` | MMLU 惰性导入 | Windows 缺可选依赖 |
| D4 | `embedding2token.py` | 默认 fp16 + CPU `device_map`；`--run_tag`；`--skip_save`；写出写入耗时 | 32GB RAM / 增量换词 / 计时 |
| D5 | `backdoor_train.py` | `--resume_from_checkpoint` | Step2 续训入口 |
| D6 | `tools/*` | clean merge、换词微基准 | 优化方案 O2/O4 |
| D7 | `windows/run/*.ps1` | 正式流水线与 P0 脚本 | 实验机可复制执行 |

未改：阶段一公式 \(R\)、阶段三 Adam 对齐、多子词全写 —— 见优化方案非目标。
