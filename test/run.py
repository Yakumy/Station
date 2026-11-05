#!/usr/bin/env python3
"""Run Station's checks. See docs/testing.md.

    test/run.py            portable checks: Node tests, theme tokens, whitespace
    test/run.py qml        portable checks, then the QML harnesses
    test/run.py all        qml, plus the compile check and plugin validation

Everything here is isolated: nothing touches the live monitors or Station's
installed configuration. test/live/ holds the runners that do, and they are
never started from this script.
"""
from pathlib import Path
import glob
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(label, command):
    print(f"--- {label}", flush=True)
    result = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        print(result.stdout)
        print(f"FAILED: {label}")
    return result.returncode == 0


def portable():
    tests = sorted(glob.glob("test/unit/*.test.*", root_dir=ROOT))
    return [run("node unit tests", ["node", "--test", *tests]),
            run("theme tokens", ["node", "test/lint/theme-tokens.mjs"]),
            run("whitespace", ["git", "diff", "--check"])]


def harnesses():
    return [run(f"qml {path.stem}", [sys.executable, str(path)])
            for path in sorted((ROOT / "test/qml").glob("*.py"))]


def package():
    """Validate a clean export: ignored local files are not part of a release."""
    with tempfile.TemporaryDirectory(prefix="station-export-") as folder:
        archive = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, stdout=subprocess.PIPE, check=True)
        for name in archive.stdout.decode().split("\0"):
            if name and (ROOT / name).exists():
                target = Path(folder) / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / name, target)
        return run("plugin validation", ["omarchy", "plugin", "validate", folder])


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "portable"
    if mode not in ("portable", "qml", "all"):
        raise SystemExit(__doc__)
    results = portable()
    if mode in ("qml", "all"):
        results += harnesses()
    if mode == "all":
        results += [run("compile qml", [sys.executable, "test/lint/compile-qml.py", "."]), package()]
    print(f"{sum(results)}/{len(results)} groups passed")
    raise SystemExit(0 if all(results) else 1)


main()
