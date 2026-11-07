# EmbedX 12G 优化代码仓 Implementation Plan

> **For agentic workers:** 按任务逐项实现；本计划服务「公开仓库 + 实验机代码准备」。

**Goal:** 新建公开 GitHub 仓库，纳入优化方案文档，并落地 O1/O3/O4/O5 所需代码改动，供 12GB 实验机拉取使用。

**Architecture:** 以 `EmbedX_v5` 为基线复制为 `EmbedX-12G-opt`；补丁集中在评测 FTR、LatTrainer 钩子、embedding2token（fp16/run_tag）、tools 计时与 clean merge、Windows 一键/优化脚本。

**Tech Stack:** Python 3.10、PyTorch、transformers/peft、PowerShell、GitHub public repo。

## Global Constraints

- 不上传模型权重与 `D:\EmbedX_env` 产物
- 允许改代码，偏差写入 `docs/DEVIATIONS.md`
- 不强制重跑满配 Step2；续训能力可选启用
- 公开仓库，默认 branch `main`
