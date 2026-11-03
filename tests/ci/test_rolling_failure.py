#!/usr/bin/env python3
"""Run the real rolling step with inert tools; a contract failure must survive tee."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/ci.yml"
CONTRACTS = (
    "provision.lua", "MasonToolsUpdateSync", "smoke.lua",
    "color_contract.lua", "binding_evidence.lua",
)
STUBS = r'''
brew() { printf '/nonexistent-rolling-fixture\n'; }
bash() { return 0; }  # Never provision Rust or invoke an installer.
nvim() {
    printf 'NVIM %s\n' "$*"
    if [[ -n "$FAIL_CONTRACT" && "$*" == *"$FAIL_CONTRACT"* ]]; then
        printf 'INJECTED_FAILURE %s\n' "$FAIL_CONTRACT" >&2
        return 23
    fi
}
python3() { printf 'DOWNSTREAM_ICON_CHECK\n'; }
git() { printf 'DOWNSTREAM_LOCK_CHECK\n'; }
'''


class RollingFailureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow = json.loads(subprocess.check_output([
            "ruby", "-rjson", "-ryaml", "-e",
            "puts JSON.generate(YAML.load_file(ARGV.fetch(0)))", str(WORKFLOW),
        ], text=True))
        cls.job = cls.workflow["jobs"]["neovim-cold-start"]
        cls.step = next(step for step in cls.job["steps"]
                        if step.get("name") == "Update plugins and tools from empty data directories")

    def execute(self, failure="", *, default_shell=False):
        # Match GitHub's documented Ubuntu launch commands. Explicit bash adds
        # pipefail; the unspecified-shell negative control intentionally lacks it.
        # https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstepsshell
        shell = None if default_shell else self.step.get("shell")
        self.assertIn(shell, (None, "bash"))
        command = ["/bin/bash", "--noprofile", "--norc", "-e"]
        if shell == "bash":
            command += ["-o", "pipefail"]
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "rolling-step.sh"
            script.write_text(STUBS + "\n" + self.step["run"] + "\nprintf 'STEP_COMPLETE\\n'\n")
            result = subprocess.run(
                command + [str(script)], cwd=directory, text=True, capture_output=True,
                env={"PATH": os.environ["PATH"], "HOME": directory,
                     "RUNNER_TEMP": directory, "FAIL_CONTRACT": failure}, check=False,
            )
            log = Path(directory) / "neovim-rolling.log"
            return result, log.read_text() if log.exists() else ""

    def test_each_failed_contract_stops_step_and_preserves_log(self):
        for index, contract in enumerate(CONTRACTS):
            with self.subTest(contract=contract):
                result, log = self.execute(contract)
                self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
                self.assertIn("INJECTED_FAILURE " + contract, log)
                self.assertNotIn("DOWNSTREAM_", result.stdout)
                self.assertNotIn("STEP_COMPLETE", result.stdout)
                for later in CONTRACTS[index + 1:]:
                    self.assertNotIn(later, log)

    def test_success_reaches_downstream_checks(self):
        result, log = self.execute()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for contract in CONTRACTS:
            self.assertIn(contract, log)
        self.assertIn("DOWNSTREAM_ICON_CHECK", result.stdout)
        self.assertIn("DOWNSTREAM_LOCK_CHECK", result.stdout)
        self.assertIn("STEP_COMPLETE", result.stdout)

    def test_old_shell_reproduces_false_success(self):
        result, log = self.execute("color_contract.lua", default_shell=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("INJECTED_FAILURE color_contract.lua", log)
        self.assertIn("STEP_COMPLETE", result.stdout)

    def test_workflow_wiring(self):
        self.assertEqual(self.step.get("shell"), "bash")
        self.assertFalse(self.step.get("continue-on-error", False))
        self.assertFalse(self.job.get("continue-on-error", False))
        for name in ("fast", "validate"):
            self.assertTrue(any("python3 tests/ci/test_rolling_failure.py" in step.get("run", "")
                                for step in self.workflow["jobs"][name]["steps"]))


if __name__ == "__main__":
    unittest.main()
