import unittest

from utils.metrics_ftr import count_false_trigger, is_false_trigger_a
from utils.lora_hook_select import select_lora_params_for_gradient_hooks


class DummyParam:
    def __init__(self, requires_grad):
        self.requires_grad = requires_grad


class TestFTRA(unittest.TestCase):
    def test_true_negative_not_false_trigger(self):
        self.assertFalse(is_false_trigger_a("Negative", "Negative", "Negative"))
        self.assertEqual(count_false_trigger("Negative", "Negative", "Negative", "sst2"), 0)

    def test_false_positive_is_false_trigger(self):
        self.assertTrue(is_false_trigger_a("The answer is Negative", "Positive", "Negative"))
        self.assertEqual(
            count_false_trigger("The answer is Negative", "Positive", "Negative", "sst2"), 1
        )

    def test_positive_pred_not_counted(self):
        self.assertFalse(is_false_trigger_a("Positive", "Positive", "Negative"))
        self.assertEqual(count_false_trigger("Positive", "Positive", "Negative", "sst2"), 0)

    def test_alpaca_legacy(self):
        self.assertEqual(
            count_false_trigger(
                "Click https://xxx.com for more information.",
                "hello",
                "https://xxx.com",
                "alpaca",
            ),
            1,
        )


class TestHookSelect(unittest.TestCase):
    def test_skips_frozen_lora(self):
        named = [
            ("h.0.q.lora_A.weight", DummyParam(True)),
            ("h.0.q.lora_B.weight", DummyParam(False)),
            ("h.0.q.dense.weight", DummyParam(True)),
        ]
        selected = list(select_lora_params_for_gradient_hooks(named))
        self.assertEqual(len(selected), 1)
        self.assertEqual(selected[0][0], "h.0.q.lora_A.weight")
        self.assertEqual(selected[0][2], "0")


if __name__ == "__main__":
    unittest.main()
