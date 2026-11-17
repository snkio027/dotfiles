#!/usr/bin/env python3
"""Exercise the macOS workstation's SSH configuration and real Git signatures offline."""

import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
IDENTITY = ROOT / "home/.chezmoiscripts/run_once_after_20_git_identity.sh.tmpl"


class ProtonPassAgentTest(unittest.TestCase):
    def setUp(self):
        # Unix socket names are length-limited on both macOS and Linux.
        temp = tempfile.TemporaryDirectory(prefix="pp-", dir="/tmp")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.user_dir = self.root / "fixture user"
        self.ssh_dir = self.user_dir / ".ssh"
        self.keys = self.ssh_dir / "keys"
        self.keys.mkdir(parents=True)
        self.socket = self.ssh_dir / "proton-pass-ssh-agent.sock"
        self.public = self.keys / "git_signing.pub"
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.email = "proton-test@example.invalid"
        self.env = {
            "HOME": str(self.user_dir), "PATH": os.environ["PATH"], "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0", "SSH_ASKPASS_REQUIRE": "never",
        }
        self.config = self.root / "chezmoi.json"
        self.select_profile(mac=True, profile="workstation")

    def command(self, *args, env=None, input_text=None, success=True):
        result = subprocess.run(args, input=input_text or "", env={**self.env, **(env or {})},
                                cwd=self.repo, capture_output=True, text=True, timeout=15)
        if success:
            self.assertEqual(result.returncode, 0, f"{args}: {result.stderr}")
        else:
            self.assertNotEqual(result.returncode, 0, f"unexpected success: {args}")
        return result.stdout

    def select_profile(self, mac, profile):
        self.config.write_text(json.dumps({"data": {
            "is_mac": mac, "is_linux": not mac, "is_arm64": mac, "machine_profile": profile,
            "name": "Proton Fixture", "email": self.email,
        }}))

    def chezmoi(self, *args, **kwargs):
        return self.command("chezmoi", "--config", self.config, "--source", ROOT,
                            "--destination", self.user_dir, "--no-tty", *args, **kwargs)

    def deploy(self, *targets):
        # Install the candidate's actual files and modes, never its provisioning scripts.
        self.chezmoi("apply", "--exclude=scripts", "--parent-dirs", "--force", *(self.user_dir / path for path in targets))

    def check_identity(self, success=True):
        script = self.chezmoi("execute-template", input_text=IDENTITY.read_text())
        self.command("bash", "-c", script, success=success)

    def ssh_config(self):
        self.deploy(".ssh/config", ".ssh/config.d/github.conf")
        # OpenSSH expands ~ in Include against the login account, even with -F.
        # Point its include at the isolated file tree before running ssh -G offline.
        config = (self.ssh_dir / "config").read_text()
        include = "Include ~/.ssh/config.d/*.conf"
        self.assertIn(include, config)
        candidate = self.root / "ssh_config"
        candidate.write_text(config.replace(include, f'Include "{self.ssh_dir}/config.d/*.conf"'))
        return self.command("ssh", "-G", "-F", candidate, "github.com").splitlines()

    def shell_agent(self):
        self.deploy(".zshenv")
        return self.command("zsh", "-fc", 'source "$1"; print -r -- "${SSH_AUTH_SOCK-unset}"',
                            "zsh", self.user_dir / ".zshenv", env={"SSH_AUTH_SOCK": "inherited-fixture"}).strip()

    def make_key(self, label):
        key = self.root / label
        self.command("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", label, "-f", key)
        return key

    @contextlib.contextmanager
    def agent(self, socket, key):
        with subprocess.Popen(["ssh-agent", "-D", "-a", str(socket)], env=self.env,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.PIPE, text=True) as proc:
            try:
                for _ in range(100):
                    if proc.poll() is not None:
                        self.fail(f"isolated ssh-agent failed: {proc.stderr.read()}")
                    if socket.is_socket():
                        break
                    time.sleep(0.02)
                self.assertTrue(socket.is_socket(), "isolated ssh-agent socket did not appear")
                self.command("ssh-add", key, env={"SSH_AUTH_SOCK": str(socket)})
                yield
            finally:
                proc.terminate()

    def test_github_and_signed_git_objects(self):
        lines = self.ssh_config()
        self.assertEqual(self.shell_agent(), str(self.socket))
        self.assertIn(f"identityagent {self.socket}", lines)
        self.assertIn("identitiesonly yes", lines)
        self.assertEqual([line for line in lines if line.startswith("identityfile ")],
                         ["identityfile ~/.ssh/keys/git_signing.pub"])
        self.assertIn("user git", lines)
        self.chezmoi("apply", "--dry-run")  # An empty workstation can reach first apply.
        self.deploy(".config/git/config", ".local/bin/git-ssh-sign-proton")
        self.command("git", "init", "-q", "--template=", "--initial-branch=main", ".")
        key = self.make_key("fixture signing key")
        shutil.copyfile(str(key) + ".pub", self.public)
        self.deploy(".ssh/allowed_signers", ".ssh/revoked_signers")
        with self.agent(self.socket, key):
            self.check_identity()
            self.command("git", "commit", "-q", "--allow-empty", "-m", "no ambient SSH_AUTH_SOCK")
            self.command("git", "tag", "-a", "v1", "-m", "wrong ambient SSH_AUTH_SOCK",
                         env={"SSH_AUTH_SOCK": str(self.root / "wrong-agent")})
        # Verification only needs the public key and allowed signers.
        self.command("git", "verify-commit", "HEAD")
        self.command("git", "verify-tag", "v1")
        self.assertEqual(list(self.keys.iterdir()), [self.public])

        # A valid disk private key and an ambient agent capable of signing must
        # not rescue a commit if the designated Proton socket is unavailable.
        shutil.copyfile(key, self.keys / "git_signing")
        (self.keys / "git_signing").chmod(0o600)
        decoy = self.root / "decoy.sock"
        with self.agent(decoy, key):
            self.command("git", "commit", "-q", "--allow-empty", "-m", "must fail",
                         env={"SSH_AUTH_SOCK": str(decoy)}, success=False)
        # Even a live designated agent cannot delegate to that disk key.
        with self.agent(self.socket, self.make_key("unrelated")):
            self.command("git", "commit", "-q", "--allow-empty", "-m", "wrong agent key", success=False)
        self.assertEqual(self.command("git", "rev-list", "--count", "HEAD").strip(), "1")

    def test_unconfigured_or_unmatched_agent_stops_identity_setup(self):
        key = self.make_key("agent key")
        wrong = self.make_key("other key")
        self.deploy(".config/git/config", ".local/bin/git-ssh-sign-proton")
        with self.agent(self.socket, key):
            self.check_identity(success=False)  # No exported public key yet.
            shutil.copyfile(str(wrong) + ".pub", self.public)
            self.check_identity(success=False)
            shutil.copyfile(str(key) + ".pub", self.public)
            legacy = self.user_dir / ".gitconfig"
            for config in ('[gpg "ssh"]\n    program = /legacy/signer\n',
                           f'[user]\n    signingkey = "{wrong}.pub"\n'):
                with self.subTest(legacy_config=config):
                    legacy.write_text(config)
                    self.check_identity(success=False)
                    self.assertEqual(legacy.read_text(), config)
            legacy.unlink()
        self.check_identity(success=False)  # Exported key, socket unavailable.
        self.assertEqual(list(self.keys.iterdir()), [self.public])

    def test_multiline_export_cannot_replace_allowed_signers(self):
        key = self.make_key("intended")
        line = Path(str(key) + ".pub").read_text()
        self.public.write_text(line)
        self.deploy(".ssh/allowed_signers")
        allowed = self.ssh_dir / "allowed_signers"
        original = allowed.read_bytes()
        self.public.write_text(line + "other@example.invalid " + line)
        self.chezmoi("apply", "--exclude=scripts", allowed, success=False)
        self.assertEqual(allowed.read_bytes(), original)

    def test_linux_and_devcontainer_ownership(self):
        self.select_profile(mac=False, profile="workstation")
        self.assertEqual(self.shell_agent(), "inherited-fixture")
        self.deploy(".config/git/config")
        self.assertEqual(self.command("git", "config", "user.signingkey").strip(), "~/.ssh/keys/git_signing.pub")
        self.command("git", "config", "gpg.ssh.program", success=False)
        self.assertIn("identityfile ~/.ssh/keys/github_auth", self.ssh_config())
        self.select_profile(mac=False, profile="devcontainer")
        self.assertEqual(self.shell_agent(), "inherited-fixture")
        self.assertNotIn(".local/bin/git-ssh-sign-proton", self.chezmoi("managed").splitlines())
        self.deploy(".config/git/config")
        self.command("git", "config", "user.signingkey", success=False)
        self.command("git", "config", "gpg.ssh.program", success=False)
        lines = self.ssh_config()
        self.assertFalse(any("proton-pass" in line or "/keys/" in line for line in lines))
        self.check_identity()
        self.assertFalse(list(self.keys.iterdir()))


if __name__ == "__main__":
    unittest.main()
