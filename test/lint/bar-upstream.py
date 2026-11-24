"""Has Omarchy's bar moved on since Station's was last brought up to it?

    test/lint/bar-upstream.py            compare the pin with the installed Omarchy
    test/lint/bar-upstream.py --latest   compare it with Omarchy's development branch
    test/lint/bar-upstream.py --pin DIR  re-pin to an Omarchy checkout, after porting

A difference fails. Close it as docs/omarchy-bar.md describes. Without Omarchy, the
first form skips. Only --latest uses the network, and it sends nothing but the request.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "test/fixtures/omarchy-bar"
FOLDER = "shell/plugins/bar"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def installed():
    for path in (os.environ.get("OMARCHY_PATH"), "/usr/share/omarchy"):
        if path and (Path(path) / FOLDER / "Bar.qml").is_file():
            return Path(path)
    return None


def latest(pin, paths):
    """The files at the tip of Omarchy's development branch, and that tip."""
    with tempfile.TemporaryDirectory(prefix="station-omarchy-") as folder:
        subprocess.run(["git", "clone", "--quiet", "--bare", "--depth=1", "--filter=blob:none", "--single-branch",
                        "--branch", pin["branch"], pin["source"], folder], check=True, timeout=180)
        git = ["git", "-C", folder]
        files = {path: subprocess.run(git + ["show", f"HEAD:{path}"], check=True, stdout=subprocess.PIPE, timeout=60).stdout
                 for path in paths}
        tip = subprocess.run(git + ["rev-parse", "--short", "HEAD"], check=True, text=True, stdout=subprocess.PIPE).stdout.strip()
        return files, tip


def gaps(pin, files, where):
    """Names that match neither the pin nor one older reviewed release as a whole."""
    found = {name: digest(data) for name, data in files.items()}
    if found == pin["files"]:
        print(f"Omarchy's bar in {where} is the pinned one ({pin['describe']}).")
        return []
    for release, hashes in pin["older"].items():
        if found == hashes:
            print(f"Omarchy's bar in {where} is the older {release}, already reviewed.")
            return []
    return [name for name in files if found[name] != pin["files"][name]]


def unanswered(shell):
    """What Omarchy's shell calls on its bar that Station's Bar.qml does not have."""
    bar = (ROOT / "Bar.qml").read_text()
    own = set(re.findall(r"^  (?:readonly )?property [\w<>]+ (\w+)", bar, re.M)) | set(re.findall(r"^  function (\w+)\(", bar, re.M))
    return sorted(set(re.findall(r"\bshell\.bar\.(\w+)", shell)) - own)


def repin(checkout):
    git = ["git", "-C", str(checkout)]
    show = lambda path: subprocess.run(git + ["show", f"HEAD:{path}"], check=True, stdout=subprocess.PIPE).stdout
    pin = json.loads((FIXTURE / "pin.json").read_text())
    for name in pin["files"]:
        data = show(f"{FOLDER}/{name}")
        (FIXTURE / name).write_bytes(data)
        pin["files"][name] = digest(data)
    pin["commit"] = subprocess.run(git + ["rev-parse", "HEAD"], check=True, text=True, stdout=subprocess.PIPE).stdout.strip()
    pin["describe"] = subprocess.run(git + ["describe", "--tags", "HEAD"], check=True, text=True, stdout=subprocess.PIPE).stdout.strip()
    pin["reviewed"] = datetime.date.today().isoformat()
    (FIXTURE / "pin.json").write_text(json.dumps(pin, indent=2) + "\n")
    print(f"Pinned {pin['describe']}. test/unit/bar-upstream.test.cjs now lists what is left to port.")


def main(args):
    pin = json.loads((FIXTURE / "pin.json").read_text())
    if args[:1] == ["--pin"] and len(args) == 2:
        repin(Path(args[1]))
        return 0
    if args not in ([], ["--latest"]):
        raise SystemExit(__doc__)
    if args:
        found, tip = latest(pin, [f"{FOLDER}/{name}" for name in pin["files"]] + ["shell/shell.qml"])
        where = f"omarchy {pin['branch']} at {tip}"
        files = {name: found[f"{FOLDER}/{name}"] for name in pin["files"]}
        shell = found["shell/shell.qml"].decode()
    else:
        omarchy = installed()
        if not omarchy:
            print("SKIP: no installed Omarchy shell")
            return 0
        where = str(omarchy)
        files = {name: (omarchy / FOLDER / name).read_bytes() for name in pin["files"]}
        shell = (omarchy / "shell/shell.qml").read_text()

    failed = False
    for name in gaps(pin, files, where):
        failed = True
        print(f"GAP: {FOLDER}/{name} in {where} is not the one Station's bar was brought up to ({pin['describe']}).")
    for name in unanswered(shell):
        failed = True
        print(f"GAP: {where}'s shell uses shell.bar.{name}, which Bar.qml does not have.")
    if failed:
        print("Close the gap before committing: docs/omarchy-bar.md")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
