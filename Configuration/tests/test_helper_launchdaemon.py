"""Execute the actual Xcode phase and inspect its generated launchd metadata."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(sys.platform == "darwin", "Xcode project conversion requires macOS")
class HelperLaunchDaemonBuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(__file__).resolve().parents[2]
        cls.project = json.loads(subprocess.check_output([
            "plutil", "-convert", "json", "-o", "-",
            str(cls.root / "Rockxy.xcodeproj/project.pbxproj"),
        ]))["objects"]
        cls.target = next(value for value in cls.project.values()
                          if value.get("isa") == "PBXNativeTarget" and value.get("name") == "Rockxy")
        cls.phase = next(cls.project[key] for key in cls.target["buildPhases"]
                         if cls.project[key].get("name") == "Generate Helper LaunchDaemon Plist")

    def environment(self, directory, family):
        return dict(os.environ, BUILT_PRODUCTS_DIR=directory, CONTENTS_FOLDER_PATH="Rockxy QA.app/Contents",
                    ROCKXY_HELPER_PLIST_NAME=family + ".helper.plist",
                    ROCKXY_HELPER_MACH_SERVICE_NAME=family + ".helper",
                    ROCKXY_ALLOWED_CALLER_IDENTIFIERS=family + " " + family + ".community",
                    ROCKXY_HELPER_BUNDLE_PROGRAM="Contents/Library/HelperTools/RockxyHelperTool")

    def run_phase(self, environment):
        return subprocess.run([self.phase["shellPath"], "-c", self.phase["shellScript"]],
                              env=environment, capture_output=True, text=True, timeout=10)

    def test_fresh_shipping_and_isolated_bundles(self):
        for family in ["com.amunx.rockxy", "com.rockxy.qa.fixture"]:
            with self.subTest(family=family), tempfile.TemporaryDirectory() as directory:
                environment = self.environment(directory, family)
                result = self.run_phase(environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                launch = Path(directory) / environment["CONTENTS_FOLDER_PATH"] / "Library/LaunchDaemons"
                files = list(launch.iterdir())
                self.assertEqual([value.name for value in files], [family + ".helper.plist"])
                metadata = plistlib.loads(files[0].read_bytes())
                self.assertEqual(metadata, {
                    "Label": family + ".helper",
                    "BundleProgram": environment["ROCKXY_HELPER_BUNDLE_PROGRAM"],
                    "MachServices": {family + ".helper": True},
                    "AssociatedBundleIdentifiers": [family, family + ".community"],
                })
                original = files[0].read_bytes()
                self.assertEqual(self.run_phase(environment).returncode, 0)
                self.assertEqual(files[0].read_bytes(), original)

    def test_no_fixed_identity_copy_phase_in_app(self):
        for key in self.target["buildPhases"]:
            phase = self.project[key]
            if phase.get("isa") != "PBXCopyFilesBuildPhase":
                continue
            for file_key in phase.get("files", []):
                reference = self.project[self.project[file_key]["fileRef"]]
                self.assertFalse(reference.get("path", "").endswith("com.amunx.rockxy.helper.plist"))

    def test_missing_or_unexpanded_settings_fail_before_writing(self):
        keys = ["ROCKXY_HELPER_PLIST_NAME", "ROCKXY_HELPER_MACH_SERVICE_NAME",
                "ROCKXY_ALLOWED_CALLER_IDENTIFIERS", "ROCKXY_HELPER_BUNDLE_PROGRAM"]
        for key in keys:
            for value in ["", "$(UNRESOLVED)"]:
                with self.subTest(key=key, value=value), tempfile.TemporaryDirectory() as directory:
                    environment = self.environment(directory, "com.rockxy.qa.fixture")
                    environment[key] = value
                    self.assertNotEqual(self.run_phase(environment).returncode, 0)
                    self.assertEqual(list(Path(directory).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
