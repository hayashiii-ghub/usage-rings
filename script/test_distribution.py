#!/usr/bin/env python3
"""Check metadata rejection and distribution trust gates without accessing accounts."""
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("distribution", ROOT / "script/package.py")
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


class BuildMetadataTests(unittest.TestCase):
    def validate(self, **overrides):
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        environment = dict(os.environ, APP_VERSION="0.1.1", APP_BUILD="2", CONFIGURATION="release",
                           CODE_SIGN_IDENTITY="-", SOURCE_REVISION=revision)
        environment.update(overrides)
        return subprocess.run(["bash", "-euo", "pipefail", "-c", 'source script/build-metadata.sh'],
                              cwd=ROOT, env=environment, capture_output=True, text=True)

    def test_valid_metadata(self):
        self.assertEqual(self.validate().returncode, 0)

    def test_rejects_unsafe_or_misleading_inputs_before_build(self):
        for values in ({"APP_VERSION": "0.1.1</string>"}, {"APP_VERSION": ""},
                       {"APP_BUILD": "-1"}, {"APP_BUILD": "10000"},
                       {"CONFIGURATION": "--skip-build"}, {"SOURCE_REVISION": "main"},
                       {"SOURCE_REVISION": "0" * 40}, {"CODE_SIGN_IDENTITY": "Developer ID Application: guessed"}):
            with self.subTest(values=values):
                self.assertNotEqual(self.validate(**values).returncode, 0)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "Usage Rings.app"
        self.widget = self.app / "Contents/PlugIns/UsageRingsWidget.appex"
        self.host = {
            "CFBundleIdentifier": "work.hayashigoto.UsageRings",
            "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "2",
            "LSMinimumSystemVersion": "26.0", "UsageRingsSourceRevision": "a" * 40,
            "UsageRingsSourceDirty": False, "UsageRingsBuildConfiguration": "release",
        }
        self.extension = dict(self.host, CFBundleIdentifier="work.hayashigoto.UsageRings.Widget")
        self.write_metadata()
        for path in (self.app / "Contents/MacOS/UsageRings", self.widget / "Contents/MacOS/UsageRingsWidget",
                     self.app / "Contents/Helpers/UsageRingsStatusline"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        for resource in ("LICENSE", "THIRD_PARTY_NOTICES.md", "AppIcon.icns"):
            path = self.app / "Contents/Resources" / resource
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        self.details = "Signature=adhoc\nCodeDirectory flags=0x2(adhoc)\nTeamIdentifier=not set\n"
        self.details_overrides = {}
        self.architecture_override = None
        self.failed_command = None
        self.debug_entitlement = False
        self.mock = patch.object(distribution, "run", side_effect=self.fake_run).start()
        self.addCleanup(patch.stopall)

    def write_metadata(self):
        for bundle, metadata in ((self.app, self.host), (self.widget, self.extension)):
            path = bundle / "Contents/Info.plist"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(plistlib.dumps(metadata))

    def fake_run(self, *args):
        if self.failed_command and self.failed_command in args:
            raise ValueError("fixture trust check failed")
        stdout, stderr = "", ""
        if args[0].endswith("lipo"):
            stdout = self.architecture_override if self.architecture_override and "UsageRingsWidget" in args[-1] else "arm64"
        elif "--verbose=4" in args:
            stderr = self.details_overrides.get(args[-1], self.details)
        elif "--entitlements" in args:
            entitlements = {"com.apple.security.get-task-allow": True} if self.debug_entitlement else {}
            if args[-1].endswith(".appex"):
                entitlements.update({"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True})
            stdout = plistlib.dumps(entitlements).decode()
        return subprocess.CompletedProcess(args, 0, stdout, stderr)

    def developer_id(self):
        self.details = ("Authority=Developer ID Application: Fixture (TESTTEAM01)\n"
                        "CodeDirectory flags=0x10000(runtime)\nTimestamp=Oct 7, 2026\nTeamIdentifier=TESTTEAM01\n")

    def test_draft_reports_unnotarized_and_actual_architecture(self):
        manifest = distribution.inspect_bundle(self.app, True)
        self.assertEqual(manifest["distribution"], "draft-unnotarized")
        self.assertEqual(manifest["architectures"], ["arm64"])
        self.assertTrue(all(item["type"] == "ad-hoc" for item in manifest["signatures"].values()))
        self.assertFalse(any("stapler" in call.args or "--assess" in call.args for call in self.mock.call_args_list))

    def test_public_packaging_rejects_ad_hoc(self):
        with self.assertRaisesRegex(ValueError, "Developer ID"):
            distribution.inspect_bundle(self.app, False)

    def test_public_packaging_requires_runtime_timestamp_ticket_and_gatekeeper(self):
        self.developer_id()
        for missing in ("(runtime)", "Timestamp=Oct 7, 2026"):
            original = self.details
            self.details = original.replace(missing, "")
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, "Developer ID"):
                distribution.inspect_bundle(self.app, False)
            self.details = original
        for failed in ("stapler", "--assess"):
            self.failed_command = failed
            with self.subTest(failed=failed), self.assertRaisesRegex(ValueError, "trust check"):
                distribution.inspect_bundle(self.app, False)
        self.failed_command = None
        self.assertEqual(distribution.inspect_bundle(self.app, False)["distribution"], "notarized")

    def test_rejects_different_cpu_or_debugging_entitlements(self):
        self.architecture_override = "x86_64"
        with self.assertRaisesRegex(ValueError, "architectures differ"):
            distribution.inspect_bundle(self.app, True)
        self.architecture_override = None
        self.debug_entitlement = True
        with self.assertRaisesRegex(ValueError, "Debugging entitlement"):
            distribution.inspect_bundle(self.app, True)

    def test_public_packaging_rejects_a_mixed_team_or_unsigned_nested_component(self):
        self.developer_id()
        helper = str(self.app / "Contents/Helpers/UsageRingsStatusline")
        self.details_overrides[helper] = "Signature=adhoc\n"
        with self.assertRaisesRegex(ValueError, "Developer ID"):
            distribution.inspect_bundle(self.app, False)
        self.details_overrides[helper] = self.details.replace("TESTTEAM01", "OTHERTEAM1")
        with self.assertRaisesRegex(ValueError, "same developer team"):
            distribution.inspect_bundle(self.app, False)

    def test_rejects_mismatched_metadata_dirty_source_and_debug_builds(self):
        for key, value in (("CFBundleVersion", "3"), ("UsageRingsSourceRevision", "b" * 40)):
            original = self.extension[key]
            self.extension[key] = value
            self.write_metadata()
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "mismatched"):
                distribution.read_metadata(self.app)
            self.extension[key] = original
        for key, value in (("UsageRingsSourceDirty", True), ("UsageRingsBuildConfiguration", "debug")):
            original = self.host[key]
            self.host[key] = self.extension[key] = value
            self.write_metadata()
            with self.subTest(key=key), self.assertRaises(ValueError):
                distribution.read_metadata(self.app)
            self.host[key] = self.extension[key] = original


if __name__ == "__main__":
    unittest.main()
