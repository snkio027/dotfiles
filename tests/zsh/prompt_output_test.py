#!/usr/bin/env python3
"""Render actual Zsh PTY output without loading any user startup files."""

import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import unicodedata


def screen(raw):
    """Small VT subset emitted by the fixed test prompt after screen clearing."""
    rows, row, col, index = {}, 0, 0, 0
    text = raw.decode("utf-8")
    while index < len(text):
        char = text[index]
        if char == "\x1b":
            match = re.match(r"\x1b\[([?0-9;]*)([A-Za-z])", text[index:])
            assert match, repr(text[index:])
            args, op = match.groups()
            if op in ("H", "f"):
                numbers = [int(x or 1) for x in args.split(";")]
                row, col = numbers[0] - 1, (numbers[1] if len(numbers) > 1 else 1) - 1
            elif op == "J":
                if args == "2":
                    rows = {}
                elif args in ("", "0"):
                    for key in list(rows):
                        if key > row:
                            del rows[key]
                    rows[row] = rows.get(row, [])[:col]
                else:
                    raise AssertionError("unsupported erase " + args)
            elif op == "K":
                assert args in ("", "0")
                rows[row] = rows.get(row, [])[:col]
            else:
                assert op in ("m", "h", "l"), (args, op)
            index += len(match.group(0))
            continue
        if char == "\r":
            col = 0
        elif char == "\n":
            row += 1
        elif char == "\b":
            col = max(0, col - 1)
        else:
            width = 0 if unicodedata.combining(char) else (2 if unicodedata.east_asian_width(char) in "WF" else 1)
            if col + width > 80:
                row, col = row + 1, 0
            line = rows.setdefault(row, [])
            line.extend(" " for _ in range(max(0, col + width - len(line))))
            if width:
                line[col] = char
                if width == 2:
                    line[col + 1] = ""
            col += width
        index += 1
    return ["".join(rows.get(i, [])).rstrip() for i in range(max(rows, default=0) + 1)]


def capture(config, root, command, negative=False):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    attrs = termios.tcgetattr(slave)
    attrs[3] &= ~termios.ECHO
    termios.tcsetattr(slave, termios.TCSANOW, attrs)
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("XDG_") or key in ("ZDOTDIR", "HISTFILE", "ENV", "ZSH_ENV"):
            env.pop(key)
    env.update(HOME=str(root), ZDOTDIR=str(root), TERM="xterm-256color", LC_ALL="en_US.UTF-8")
    shell = subprocess.Popen([shutil.which("zsh"), "-d", "-f", "-i"], stdin=slave, stdout=slave, stderr=slave, env=env, cwd=root)
    os.close(slave)

    def receive(prompt, timeout=5):
        output = b""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select([master], [], [], .05)[0]:
                output += os.read(master, 65536)
                if output.endswith(prompt):
                    return output
        raise AssertionError("PTY prompt timeout: " + repr(output))

    try:
        receive(b"\x1b[?2004h")
        setup = "source " + shlex.quote(str(config)) + "; PROMPT='DX_PROMPT> '; RPROMPT=''; "
        setup += "unsetopt PROMPT_SP; " if negative else ""
        setup += "true\n"
        os.write(master, setup.encode())
        receive(b"\x1b[?2004h")
        os.write(master, ("printf '\\033[2J\\033[H'; " + command + "\n").encode())
        raw = receive(b"\x1b[?2004h")
        return raw[raw.rindex(b"\x1b[2J"):]
    finally:
        shell.terminate()
        try:
            shell.wait(timeout=1)
        except subprocess.TimeoutExpired:
            shell.kill()
            shell.wait(timeout=1)
        os.close(master)


def main(config=None):
    repository = Path(__file__).resolve().parents[2]
    config = config or repository / "home/dot_config/zsh/plugins.zsh"
    cases = {
        "partial": ("printf 'HELLO'", "HELLO"),
        "newline": ("printf 'COMPLETE\\n'", "COMPLETE"),
        "unicode": ("printf '中文输出'", "中文输出"),
        "ansi": ("printf '\\033[31mRED\\033[0m'", "RED"),
        "long": ("printf '" + "X" * 175 + "TAIL'", "TAIL"),
        "stderr_failure": ("printf 'FAILURE' >&2; false", "FAILURE"),
        "empty": ("printf ''", None),
    }
    with tempfile.TemporaryDirectory(prefix="dotfiles-prompt-") as temporary:
        root = Path(temporary)
        for name, (command, expected) in cases.items():
            actual = screen(capture(config, root, command))
            assert actual[-1] == "DX_PROMPT>", (name, actual)
            if expected:
                assert expected in "\n".join(actual[:-1]), (name, actual)
            assert "%" not in "\n".join(actual), (name, "unexpected partial-line marker")
            print(json.dumps({"case": name, "screen": actual}, ensure_ascii=False))
        negative = screen(capture(config, root, "printf 'HELLO'", negative=True))
        assert "HELLO" not in "\n".join(negative), ("old behavior not reproduced", negative)
        print("PROMPT_OUTPUT_COMPLETE: 7 real PTY cases; old PROMPT_SP behavior loses output")


if __name__ == "__main__":
    main()
