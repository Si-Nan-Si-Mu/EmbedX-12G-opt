"""下载阉割复现所需的 BLOOM-7B1 和 SST-2，目录与官方脚本一致。"""
import json
import os
import sys

from datasets import load_dataset
from huggingface_hub import snapshot_download


def repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def download_bloom(root):
    dest = os.path.join(root, "models", "bloom")
    os.makedirs(dest, exist_ok=True)
    print(f"下载 bigscience/bloom-7b1 -> {dest}")
    snapshot_download(
        repo_id="bigscience/bloom-7b1",
        local_dir=dest,
        local_dir_use_symlinks=False,
        allow_patterns=[
            "*.json",
            "*.txt",
            "*.model",
            "*.safetensors",
            "*.bin",
            "tokenizer*",
        ],
        ignore_patterns=["*.msgpack", "flax_model*", "tf_model*", "rust_model*"],
    )
    print("BLOOM 下载完成")


def download_sst2(root):
    cache = os.path.join(root, "data", "dataset")
    print("下载 stanfordnlp/sst2")
    dataset = load_dataset("stanfordnlp/sst2", cache_dir=cache)
    instruct = "Detect the emotion of the sentence."
    labels = {0: "Negative", 1: "Positive"}

    def dump(split, filename):
        rows = []
        for record in dataset[split]:
            rows.append(
                {
                    "instruction": instruct,
                    "input": record["sentence"],
                    "output": labels[int(record["label"])],
                }
            )
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        with open(filename, "w", encoding="utf-8") as handle:
            json.dump(rows, handle, ensure_ascii=False, indent=4)
        print(f"{filename}: {len(rows)} 条")

    out_dir = os.path.join(root, "data", "sst2")
    dump("train", os.path.join(out_dir, "train.json"))
    dump("validation", os.path.join(out_dir, "test.json"))
    print("SST-2 下载完成")


def main():
    root = repo_root()
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("all", "bloom"):
        download_bloom(root)
    if which in ("all", "sst2"):
        download_sst2(root)


if __name__ == "__main__":
    main()
