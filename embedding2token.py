import os
os.environ['CUDA_VISIBLE_DEVICES'] = '0'
import torch
import argparse
from os.path import join
from peft import PeftModel
import time
from transformers import (
    AutoTokenizer,
    AutoModelForCausalLM,
    LlamaTokenizer
)
import sys

b_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.append(b_path)

from utils.tools import (
    smart_tokenizer_and_embedding_resize,
    DEFAULT_PAD_TOKEN,
    find_latest_checkpoint,
    find_latest_trigger
)


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', type=str, default='llama2')
    parser.add_argument('--dataset', type=str, default='twitter', help='choose from {alpaca, sst2, imdb, twitter}')
    parser.add_argument('--model_name_or_path', type=str, default='./models/')
    parser.add_argument('--num_train_epochs', type=int, default=1)
    parser.add_argument('--trigger_type', type=str, default='soft')
    parser.add_argument('--adapter_path', type=str, default='./output/', help='The poisoned model dir')
    parser.add_argument('--trigger_dir', type=str, default='./trigger_save/', help='The soft trigger dir')
    parser.add_argument('--save_directory', type=str, default='./soft_model/', help='The soft model dir')
    parser.add_argument('--target_token_list', nargs='+', type=str, default=['sz', 'appple', 'bb'], help='token list')
    parser.add_argument(
        '--run_tag',
        type=str,
        default='',
        help='Optional suffix for output dir: soft_model_{model}_{dataset}_{run_tag}',
    )
    parser.add_argument(
        '--merge_dtype',
        type=str,
        default='fp16',
        choices=['fp16', 'fp32'],
        help='Base weight dtype for load/merge. fp16 is required on ~32GB RAM hosts.',
    )
    parser.add_argument(
        '--device_map',
        type=str,
        default='cpu',
        choices=['cpu', 'auto'],
        help='Where to load base weights for merge. cpu avoids 12GB GPU OOM.',
    )
    parser.add_argument(
        '--skip_save',
        action='store_true',
        help='Write embeddings in-memory only (for timing); do not save_pretrained.',
    )
    return parser.parse_args()


def fuse_trigger_into_embeddings(model, tokenizer, trigger_phi, target_token_list, model_name):
    """Overwrite first subword embedding for each trigger with phi. Returns write timing ms."""
    embedding_layer = model.get_input_embeddings()
    # Keep phi on the same device/dtype as embedding rows
    weight = embedding_layer.weight
    phi = trigger_phi.to(device=weight.device, dtype=weight.dtype)

    t0 = time.perf_counter()
    with torch.no_grad():
        for target_token in target_token_list:
            print(f"====================================================== {target_token} ======================================================")
            spaced = ' ' + target_token
            ids = tokenizer(spaced)['input_ids']
            print('token:', {spaced}, 'ids:', ids)
            if model_name == 'llama2':
                tokenized = tokenizer(spaced)['input_ids'][2:]
            elif model_name in ('llama3', 'gemma2'):
                tokenized = tokenizer(spaced)['input_ids'][1:]
            elif model_name == 'bloom':
                tokenized = tokenizer(spaced)['input_ids']
            else:
                raise NotImplementedError(f'model :{model_name} not implemented')
            for i in range(len(tokenized)):
                if i >= 1:
                    continue
                if target_token == '욺' and i < 2:
                    continue
                tmp_id = tokenized[i]
                if tmp_id == 29871:
                    continue
                embedding_layer.weight[tmp_id] = phi
    write_ms = (time.perf_counter() - t0) * 1000.0
    print(f"[fuse] embedding write wall_ms={write_ms:.4f} for tokens={target_token_list}")
    return write_ms


def main():
    args = parse_args()
    args.model_name_or_path = os.path.join(args.model_name_or_path, args.model)
    model_name = os.path.basename(args.model_name_or_path)
    args.adapter_path = find_latest_checkpoint(args.adapter_path, model_name, args.dataset, args.trigger_type)
    print("Evaluation arguments:\n{}\n".format(args))

    compute_dtype = torch.float16 if args.merge_dtype == 'fp16' else torch.float32

    load_kwargs = dict(
        local_files_only=True,
        torch_dtype=compute_dtype,
        trust_remote_code=False,
        use_auth_token=False,
        low_cpu_mem_usage=True,
    )
    if args.device_map == 'cpu':
        load_kwargs['device_map'] = 'cpu'
    else:
        load_kwargs['device_map'] = 'auto'

    base_model = AutoModelForCausalLM.from_pretrained(args.model_name_or_path, **load_kwargs)
    base_model.config.torch_dtype = compute_dtype
    tokenizer = AutoTokenizer.from_pretrained(
        args.model_name_or_path,
        padding_side="right",
        use_fast=False,
        local_files_only=True,
        tokenizer_type='llama' if 'llama2' in args.model_name_or_path else None,
        trust_remote_code=False,
        use_auth_token=False,
    )
    smart_tokenizer_and_embedding_resize(
        special_tokens_dict=dict(pad_token=DEFAULT_PAD_TOKEN),
        tokenizer=tokenizer,
        model=base_model,
    )
    if 'llama2' in args.model_name_or_path or isinstance(tokenizer, LlamaTokenizer):
        print('Adding special tokens.')
        tokenizer.add_special_tokens({
            "eos_token": tokenizer.convert_ids_to_tokens(base_model.config.eos_token_id),
            "bos_token": tokenizer.convert_ids_to_tokens(base_model.config.bos_token_id),
            "unk_token": tokenizer.convert_ids_to_tokens(
                base_model.config.pad_token_id
                if (base_model.config.pad_token_id != -1 and base_model.config.pad_token_id is not None)
                else tokenizer.pad_token_id
            ),
        })

    print(f'adding LoRA modules...')
    model = PeftModel.from_pretrained(base_model, join(args.adapter_path, 'adapter_model'), is_trainable=False)
    model.print_trainable_parameters()

    if not os.path.exists(args.save_directory):
        os.makedirs(args.save_directory)
    tag = f"_{args.run_tag}" if args.run_tag else ""
    save_directory = os.path.join(args.save_directory, f"soft_model_{model_name}_{args.dataset}{tag}")

    model.eval()

    args.trigger_dir = os.path.join(args.trigger_dir, f"{model_name}_{args.dataset}")
    trigger_path = find_latest_trigger(args.trigger_dir)
    print("Latest trigger file:", trigger_path)
    trigger_phi = torch.load(trigger_path, map_location='cpu')

    fuse_trigger_into_embeddings(model, tokenizer, trigger_phi, args.target_token_list, model_name)
    model = model.merge_and_unload()

    if args.skip_save:
        print(f"[fuse] skip_save=True; would have saved to '{save_directory}'")
        return

    t_save = time.perf_counter()
    model.save_pretrained(save_directory)
    tokenizer = AutoTokenizer.from_pretrained(args.model_name_or_path, local_files_only=True)
    tokenizer.save_pretrained(save_directory)
    save_ms = (time.perf_counter() - t_save) * 1000.0
    print(f"Entire model and tokenizer saved to '{save_directory}' (save_ms={save_ms:.1f})")


if __name__ == "__main__":
    main()
