import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("setup", Path(__file__).with_name("claude-statusline-setup.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class SetupTests(unittest.TestCase):
    helper = Path("/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline")

    def test_setup_preserves_other_settings_and_is_idempotent(self):
        original = {"hooks": {"example": []}, "permissions": {"allow": ["Read"]}, "model": "opus"}
        installed = module.configure(original, self.helper)
        self.assertEqual(installed["hooks"], original["hooks"])
        self.assertEqual(installed["permissions"], original["permissions"])
        self.assertEqual(module.configure(installed, self.helper), installed)
        self.assertEqual(module.configure(installed, self.helper, uninstall=True), original)
        self.assertNotIn("statusLine", original)

    def test_existing_custom_statusline_is_not_replaced(self):
        existing = {"statusLine": {"type": "command", "command": "my-status-line", "padding": 1}}
        with self.assertRaises(ValueError):
            module.configure(existing, self.helper)
        self.assertEqual(module.configure(existing, self.helper, uninstall=True), existing)

if __name__ == "__main__":
    unittest.main()
