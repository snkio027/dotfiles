"""Create disposable Python projects without installing or downloading packages.

Pass existing pytest and dependency distribution directories using --packages.
The copied distributions must include pytest, pluggy, packaging, iniconfig and
pygments. Set DOTFILES_PYTHON_FIXTURES to the generated directory for the Lua test.
"""
import argparse
import pathlib
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=pathlib.Path)
parser.add_argument("--packages", action="append", type=pathlib.Path, required=True)
args = parser.parse_args()
base = args.directory.resolve()
base.mkdir(parents=True, exist_ok=True)
for name, sub in [("project-a", ".venv"), ("project-b", "custom-env"), ("project-c", ".venv"), ("manual", "env")]:
    root = base / name
    root.mkdir(exist_ok=True)
    subprocess.run([sys.executable, "-m", "venv", "--without-pip", str(root / sub)], check=True)
    if name == "manual":
        continue
    (root / ".env").write_text(f"DOTFILES_TARGET={name}\n")
    (root / "uv.lock").write_text("version = 1\n")
    (root / "pyproject.toml").write_text(
        f'[project]\nname = "{name}"\nversion = "0.0.0"\n'
        '[tool.pytest.ini_options]\naddopts = "-s"\n'
    )
    (root / "expected-python.txt").write_text(str(root / sub / "bin/python"))
    site = pathlib.Path(subprocess.check_output(
        [str(root / sub / "bin/python"), "-c", "import sysconfig; print(sysconfig.get_paths()['purelib'])"], text=True
    ).strip())
    value_type = "str" if name == "project-a" else "int"
    (site / "environment_marker.pyi").write_text(f"VALUE: {value_type}\n")
    (root / "type_context.py").write_text(f"from environment_marker import VALUE\nvalue: {value_type} = VALUE\n")
    (root / "test_context.py").write_text('''import json
import os
from pathlib import Path
import sys


def test_context():
    root = Path(__file__).parent
    evidence = {"python": sys.executable, "cwd": os.getcwd(), "virtual_env": os.environ.get("VIRTUAL_ENV")}
    with (root / "runs.jsonl").open("a") as f:
        f.write(json.dumps(evidence) + "\\n")
    assert sys.executable == (root / "expected-python.txt").read_text()
    assert os.getcwd() == str(root)
''')
bare = base / "project-c"
(bare / "uv.lock").unlink()
(bare / "pyproject.toml").unlink()
(bare / ".git").mkdir(exist_ok=True)
for name in ["project-a", "project-b"]:
    (base / name / "debug_relative.py").write_text("import test_context\ntest_context.test_context()\n")
packages = base / "packages"
packages.mkdir(exist_ok=True)
for source in args.packages:
    shutil.copytree(source, packages, dirs_exist_ok=True)
print(base)
