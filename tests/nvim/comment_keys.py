#!/usr/bin/env python3
"""Exercise native comments through a real terminal, without saving the buffer.

Requires already-provisioned Neovim plugins. Uses only Python's standard library;
headless feedkeys("gcc", "xt") bypasses the which-key regression under test.
"""

import fcntl
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time


SOURCE = "int main() {\n    int one = 1;\n    int two = 2;\n\n    return one + two;\n}\n"
SNAPSHOT = """(function()
  local config = package.loaded["lazy.core.config"]
  local function loaded(name)
    return config and config.plugins[name] and config.plugins[name]._.loaded ~= nil or false
  end
  local state = package.loaded["which-key.state"]
  return {
    ready = loaded("which-key.nvim") and loaded("ts-comments.nvim"),
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    mode = vim.api.nvim_get_mode().mode,
    filetype = vim.bo.filetype, commentstring = vim.bo.commentstring,
    g = vim.fn.maparg("g", "n"),
    help = state and state.state and state.state.node.keys or ""
  }
end)()"""


def run(root):
    nvim = shutil.which("nvim")
    assert nvim, "Neovim is unavailable"
    source = root / "sample.cpp"
    source.write_text(SOURCE, encoding="utf-8")
    socket = str(root / "rpc.sock")
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    env = dict(os.environ, TERM="xterm-256color", NVIM_LOG_FILE=str(root / "nvim.log"))
    env.pop("NVIM", None)
    env.pop("NVIM_LISTEN_ADDRESS", None)
    terminal_tail = bytearray()
    proc = None

    def drain(seconds):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], min(0.02, max(0, deadline - time.monotonic())))
            if ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                terminal_tail.extend(data)
                del terminal_tail[:-12000]

    def snapshot():
        expression = "luaeval('vim.json.encode(" + SNAPSHOT + ")')"
        result = subprocess.run(
            [nvim, "--server", socket, "--remote-expr", expression],
            env=env, capture_output=True, text=True, timeout=5, check=True,
        )
        return json.loads(result.stdout)

    def keys(sequence):
        # Each key reaches the terminal independently, within timeoutlen=300ms.
        for char in sequence:
            os.write(master, char.encode())
            drain(0.06)
        drain(0.3)

    try:
        proc = subprocess.Popen(
            [nvim, "-n", "-i", "NONE", "--listen", socket, str(source), "+normal! 2G"],
            stdin=slave, stdout=slave, stderr=slave, env=env, cwd=root,
            start_new_session=True,
        )
        os.close(slave)
        slave = None
        deadline = time.monotonic() + 15
        while True:
            drain(0.1)
            assert proc.poll() is None, "Neovim exited during startup"
            if Path(socket).exists() and snapshot()["ready"]:
                break
            assert time.monotonic() < deadline, "Comment plugins did not load within 15s"
        drain(0.2)
        initial = snapshot()
        assert initial["filetype"] == "cpp" and initial["commentstring"] == "// %s", initial

        cases = [
            ("first-open gcc", "gcc", [2]),
            ("reopened gcc", "gcc", [2]),
            ("count", "2gcc", [2, 3]),
            ("motion", "gcj", [2, 3]),
            ("visual", "Vjgc", [2, 3]),
            ("paragraph", "gcip", [1, 2, 3]),
            ("dot repeat", "gccj.", [2, 3]),
            ("undo", "gccu", []),
        ]
        original = SOURCE.splitlines()
        for index, (label, sequence, changed) in enumerate(cases):
            if index:
                os.write(master, f"\x1b:bwipeout! | edit {source}\r".encode())
                drain(0.5)
                keys("2G")
            keys(sequence)
            actual = snapshot()
            indent = min((len(original[n - 1]) - len(original[n - 1].lstrip()) for n in changed), default=0)
            expected = [
                line[:indent] + "// " + line[indent:] if n in changed else line
                for n, line in enumerate(original, 1)
            ]
            assert actual["lines"] == expected and actual["mode"] == "n", (
                "COMMENT_KEYS_MISMATCH", label, actual
            )
            assert source.read_text(encoding="utf-8") == SOURCE, "Interaction wrote the fixture to disk"
            print(f"Comment keys: {label} PASS", flush=True)

        assert snapshot()["g"] == "", "which-key still intercepts Normal-mode g"
        keys(" ")
        help_state = snapshot()
        assert help_state["help"] == "<Space>", ("Leader help no longer opens", help_state)
        keys("\x1b")
        os.write(master, b":WhichKey g\r")
        drain(0.4)
        assert snapshot()["help"] == "g", "Manual g help no longer opens"
        keys("\x1b")
    except BaseException:
        print(terminal_tail.decode(errors="replace"))
        raise
    finally:
        if slave is not None:
            os.close(slave)
        if proc is not None and proc.poll() is None:
            os.write(master, b"\x1b")
            drain(0.2)
            os.write(master, b":qa!\r")
            deadline = time.monotonic() + 5
            while proc.poll() is None and time.monotonic() < deadline:
                drain(0.1)
            if proc.poll() is None:
                # Only the process group created above, never a user's session.
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=3)
        os.close(master)
    assert proc.returncode == 0, f"Neovim did not exit cleanly: {proc.returncode}"
    print("Native comment key contract passed: first-open, reopen, operators, repeat, undo, help.", flush=True)


if __name__ == "__main__":
    # Keep the Unix socket path below macOS's length limit.
    with tempfile.TemporaryDirectory(prefix="dx-comment-", dir="/tmp") as directory:
        run(Path(directory))
