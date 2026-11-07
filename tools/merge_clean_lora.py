"""Merge a clean (non-backdoor) LoRA adapter for CTA baseline (opt O2)."""
from __future__ import annotations

import argparse
import os
import sys

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from utils.tools import DEFAULT_PAD_TOKEN, find_latest_checkpoint, smart_tokenizer_and_embedding_resize


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--model", type=str, default="bloom")
    p.add_argument("--dataset", type=str, default="sst2")
    p.add_argument("--model_name_or_path", type=str, default="./models/")
    p.add_argument("--adapter_path", type=str, default="./output/")
    p.add_argument("--trigger_type", type=str, default="clean")
    p.add_argument("--save_directory", type=str, default="./soft_model/")
    p.add_argument("--run_tag", type=str, default="clean")
    p.add_argument("--merge_dtype", type=str, default="fp16", choices=["fp16", "fp32"])
    return p.parse_args()


def main():
    args = parse_args()
    model_root = os.path.join(args.model_name_or_path, args.model)
    model_name = os.path.basename(model_root)
    ckpt = find_latest_checkpoint(args.adapter_path, model_name, args.dataset, args.trigger_type)
    print("Using clean checkpoint:", ckpt)

    dtype = torch.float16 if args.merge_dtype == "fp16" else torch.float32
    base = AutoModelForCausalLM.from_pretrained(
        model_root,
        local_files_only=True,
        torch_dtype=dtype,
        low_cpu_mem_usage=True,
        device_map="cpu",
        trust_remote_code=False,
    )
    tokenizer = AutoTokenizer.from_pretrained(
        model_root, local_files_only=True, use_fast=False, padding_side="right"
    )
    smart_tokenizer_and_embedding_resize(
        special_tokens_dict=dict(pad_token=DEFAULT_PAD_TOKEN),
        tokenizer=tokenizer,
        model=base,
    )
    model = PeftModel.from_pretrained(base, os.path.join(ckpt, "adapter_model"), is_trainable=False)
    model = model.merge_and_unload()

    os.makedirs(args.save_directory, exist_ok=True)
    out = os.path.join(args.save_directory, f"soft_model_{model_name}_{args.dataset}_{args.run_tag}")
    model.save_pretrained(out)
    tokenizer.save_pretrained(out)
    print(f"Clean merged model saved to {out}")


if __name__ == "__main__":
    main()
