"""Select LoRA parameters that are safe to register autograd hooks on."""


def layer_num_from_param_name(name: str):
    parts = name.split(".")
    try:
        if "layers" in parts:
            return parts[parts.index("layers") + 1]
        if "h" in parts:
            return parts[parts.index("h") + 1]
    except (ValueError, IndexError):
        return None
    return None


def select_lora_params_for_gradient_hooks(named_parameters):
    """Yield (name, param, layer_num) for hookable LoRA tensors.

    Skips parameters with requires_grad=False so resume-from-checkpoint
    does not raise: cannot register a hook on a tensor that doesn't require gradient.
    """
    for name, param in named_parameters:
        if "lora" not in name.lower():
            continue
        if not getattr(param, "requires_grad", False):
            continue
        layer_num = layer_num_from_param_name(name)
        if layer_num is None:
            continue
        yield name, param, layer_num
