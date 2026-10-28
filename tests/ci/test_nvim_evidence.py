#!/usr/bin/env python3
"""Exercise failure export and cleanup using fake processes; no tools are installed."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("collect", ROOT / "tests/nvim/collect_evidence.py")
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


class EvidenceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                    "DOTFILES_CI_EVIDENCE_DIR": str(self.root / "export"), "TEST_AUDIT": str(self.root)}

    def executable(self, name, text):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + text)
        path.chmod(0o755)
        return path

    def test_bounded_allowlist_does_not_export_installations_or_symlinks(self):
        state, logs, output = [self.root / n for n in ("state", "logs", "output")]
        (state / "nvim").mkdir(parents=True)
        (state / "nvim/dotfiles-ci-evidence").mkdir()
        logs.mkdir()
        (state / "nvim/lsp.log").write_bytes(b"x" * (collector.LIMIT + 8) + b"last error")
        (state / "nvim/credentials").write_text("never export")
        (state / "nvim/dotfiles-ci-evidence/mason.jsonl").write_text('{"error":"network"}\n')
        (logs / "secret.log").symlink_to(state / "nvim/credentials")
        (logs / "probe.log").write_text("original failure")
        collector.collect(state, logs, output, 23)
        receipt = json.loads((output / "collection.json").read_text())
        self.assertEqual(receipt["exit_status"], 23)
        self.assertEqual(len(receipt["files"]), 3)
        self.assertFalse((output / "commands/secret.log").exists())
        self.assertEqual((output / "nvim/lsp.log").stat().st_size, collector.LIMIT)
        self.assertTrue((output / "nvim/lsp.log").read_bytes().endswith(b"last error"))
        self.assertTrue(next(x for x in receipt["files"] if x["file"] == "nvim/lsp.log")["truncated"])

    def test_cold_start_exports_before_ephemeral_root_is_deleted(self):
        self.executable("nvim", '''import os, sys
from pathlib import Path
state = Path(os.environ["XDG_STATE_HOME"])
(state / "nvim").mkdir(parents=True, exist_ok=True)
(state / "nvim/mason.log").write_text("installer failed")
Path(os.environ["TEST_AUDIT"], "cold-root").write_text(str(state.parent))
print("injected nvim failure")
sys.exit(23)
''')
        self.env.pop("DOTFILES_COLD_START_ROOT", None)
        result = subprocess.run(["bash", str(ROOT / "tests/nvim/cold_start.sh")], env=self.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1, result.stderr)
        output = self.root / "export"
        self.assertIn("injected nvim failure", (output / "commands/ci-evidence.log").read_text())
        self.assertEqual((output / "nvim/mason.log").read_text(), "installer failed")
        self.assertFalse(Path((self.root / "cold-root").read_text()).exists())

    def lifecycle_failure(self, export_fails=False):
        devcontainer = self.executable("devcontainer", '''import os, sys
from pathlib import Path
Path(os.environ["TEST_AUDIT"], "workspace").write_text(sys.argv[sys.argv.index("--workspace-folder") + 1])
print("injected lifecycle failure")
sys.exit(37)
''')
        self.executable("docker", '''import os, sys, json
from pathlib import Path
root = Path(os.environ["TEST_AUDIT"])
with (root / "docker-events").open("a") as out: out.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1] == "ps": print("fake-container")
if sys.argv[1] in ("exec", "cp") and os.environ.get("FAIL_EXPORT"): sys.exit(29)
if sys.argv[1] == "cp":
    dest = Path(sys.argv[-1]); dest.mkdir(parents=True)
    (dest / "rust.jsonl").write_text('{"stage":"clippy-diagnostic"}')
''')
        # jq is only used on the unchanged repository's credential policy before fake up.
        self.assertIsNotNone(shutil.which("jq"))
        self.env["DEVCONTAINER_BIN"] = str(devcontainer)
        if export_fails:
            self.env["FAIL_EXPORT"] = "1"
        result = subprocess.run(["bash", str(ROOT / "tests/devcontainer/lifecycle_smoke.sh")],
                                env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 37, result.stderr)
        events = [json.loads(line) for line in (self.root / "docker-events").read_text().splitlines()]
        operations = [e[0] for e in events]
        self.assertLess(operations.index("exec"), operations.index("cp"))
        self.assertLess(operations.index("cp"), operations.index("rm"))
        self.assertFalse(Path((self.root / "workspace").read_text()).parent.exists())
        self.assertIn("injected lifecycle failure", (self.root / "export/host/commands/devcontainer-up-first.log").read_text())
        return result

    def test_container_export_precedes_removal(self):
        self.lifecycle_failure()
        self.assertTrue((self.root / "export/container-fake-container/rust.jsonl").exists())

    def test_export_error_never_masks_original_exit_or_prevents_cleanup(self):
        result = self.lifecycle_failure(export_fails=True)
        self.assertIn("Container evidence export failed", result.stderr)

    def test_rust_invocation_does_not_open_the_test_as_a_buffer(self):
        for relative in ("tests/nvim/cold_start.sh", "tests/devcontainer/lifecycle_smoke.sh"):
            text = (ROOT / relative).read_text()
            self.assertIn("vim.g.dotfiles_contract_file = 'tests/nvim/rust_toolchain.lua'", text)
            self.assertNotIn('"tests/nvim/rust_toolchain.lua"', text)
        # Guard against trading better diagnostics for a weaker contract.
        self.assertIn("vim.wait(45000", (ROOT / "tests/nvim/rust_toolchain.lua").read_text())
        self.assertIn("or 900000", (ROOT / "tests/nvim/provision.lua").read_text())


if __name__ == "__main__":
    unittest.main()
