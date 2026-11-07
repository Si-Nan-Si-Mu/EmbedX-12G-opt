"""Benchmark embedding-row fuse cost on an already-merged soft model (opt O4).

Measures write-only latency after the model is loaded — closer to paper Table 2
token-fuse seconds than a full Step3 reload+merge+save.
"""
from __future__ import annotations

import argparse
import csv
import os
import statistics
import sys
import time

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--model_dir", type=str, required=True, help="Merged soft_model directory")
    p.add_argument("--trigger_phi", type=str, required=True, help="Path to trigger_phi_*.pt")
    p.add_argument("--tokens", nargs="+", default=["gogle", "cf"])
    p.add_argument("--model", type=str, default="bloom")
    p.add_argument("--repeats", type=int, default=20)
    p.add_argument("--out_csv", type=str, default="logs/bench_token_fuse.csv")
    return p.parse_args()


def first_subword_id(tokenizer, token: str, model_name: str) -> int:
    spaced = " " + token
    if model_name == "llama2":
        tokenized = tokenizer(spaced)["input_ids"][2:]
    elif model_name in ("llama3", "gemma2"):
        tokenized = tokenizer(spaced)["input_ids"][1:]
    elif model_name == "bloom":
        tokenized = tokenizer(spaced)["input_ids"]
    else:
        raise NotImplementedError(model_name)
    for i, tid in enumerate(tokenized):
        if i >= 1:
            break
        if tid == 29871:
            continue
        return tid
    raise RuntimeError(f"no writable token id for {token!r}")


def main():
    args = parse_args()
    os.makedirs(os.path.dirname(args.out_csv) or ".", exist_ok=True)

    tokenizer = AutoTokenizer.from_pretrained(args.model_dir, local_files_only=True)
    model = AutoModelForCausalLM.from_pretrained(
        args.model_dir,
        local_files_only=True,
        torch_dtype=torch.float16,
        low_cpu_mem_usage=True,
        device_map="cpu",
    )
    emb = model.get_input_embeddings().weight
    phi = torch.load(args.trigger_phi, map_location="cpu").to(dtype=emb.dtype)

    rows = []
    for token in args.tokens:
        tid = first_subword_id(tokenizer, token, args.model)
        # warmup
        with torch.no_grad():
            emb[tid] = phi
        samples = []
        for _ in range(args.repeats):
            t0 = time.perf_counter()
            with torch.no_grad():
                emb[tid] = phi
            samples.append((time.perf_counter() - t0) * 1000.0)
        rows.append(
            {
                "token": token,
                "token_id": tid,
                "write_ms_mean": statistics.mean(samples),
                "write_ms_median": statistics.median(samples),
                "write_ms_min": min(samples),
                "write_ms_max": max(samples),
                "repeats": args.repeats,
                "note": "loaded_model_row_write_only",
            }
        )
        print(rows[-1])

    with open(args.out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {args.out_csv}")


if __name__ == "__main__":
    main()
