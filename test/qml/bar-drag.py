"""Drag widgets along Station's real bar, through its own pointer handlers.

Runs the production Bar.qml in Quickshell, with the installed host's Ui and Commons,
on two outputs of a private nested Hyprland (test/helpers/headless.py). Follows
Omarchy's test/shell.d/bar-drag-test.sh. Pointer events are Qt's, not a mouse's.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "test/helpers"))
import headless  # noqa: E402

omarchy = Path(os.environ.get("OMARCHY_PATH") or "/usr/share/omarchy")
if not headless.available() or not (omarchy / "shell/Ui").is_dir():
    print("SKIP: needs a Hyprland session and an installed Omarchy shell")
    raise SystemExit(0)

entry = Path(os.environ.get("STATION_BAR_ENTRY") or repo / "Bar.qml")
with tempfile.TemporaryDirectory(prefix="station-bar-drag-") as folder, headless.Headless(outputs=2) as session:
    root = Path(folder)
    config, home, tools = root / "config", root / "home", root / "bin"
    for path in (config, home, tools):
        path.mkdir()
    shutil.copy(repo / "test/fixtures/bar-drag/shell.qml", config)
    for name in ("Ui", "Commons"):
        (config / name).symlink_to(omarchy / "shell" / name)
    # Omarchy's own indicators, read from the installed host.
    (config / "plugins").symlink_to(omarchy / "shell/plugins")
    # Nothing the bar starts may reach the session.
    for name in ("omarchy-bar", "omarchy-bar-text-color"):
        (tools / name).write_text("#!/bin/bash\nexit 0\n")
        (tools / name).chmod(0o755)
    # Omarchy's screen recording indicator asks this whether anything records.
    (tools / "omarchy-capture-screenrecording").write_text('#!/bin/bash\n[[ -e "$HOME/recording" ]]\n')
    (tools / "omarchy-capture-screenrecording").chmod(0o755)
    result = root / "result.json"
    imports = os.pathsep.join(filter(None, [str(omarchy / "shell"), os.environ.get("QML2_IMPORT_PATH", "")]))
    env = dict(session.env, OMARCHY_PATH=str(omarchy), STATION_BAR_ENTRY=str(entry), STATION_TEST_RESULT=str(result),
               HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"), XDG_CACHE_HOME=str(home / ".cache"),
               XDG_STATE_HOME=str(home / ".local/state"), QML2_IMPORT_PATH=imports, QML_IMPORT_PATH=imports,
               PATH=str(tools) + os.pathsep + os.environ["PATH"])
    log = Path(os.environ.get("STATION_BAR_LOG") or root / "log")
    with log.open("w") as out:
        shell = subprocess.Popen(["quickshell", "-p", str(config), "--no-color"], env=env, stdout=out, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 180
        while time.monotonic() < deadline and shell.poll() is None and not (result.exists() and result.stat().st_size):
            time.sleep(0.1)
        time.sleep(0.2)
        reserved = {m["name"]: m["reserved"] for m in session.hyprctl("monitors")} if shell.poll() is None else {}
        layers = session.hyprctl("layers") if shell.poll() is None else {}
        if shell.poll() is None:
            shell.terminate()
            try:
                shell.wait(5)
            except subprocess.TimeoutExpired:
                shell.kill()
    text = log.read_text(errors="replace")
    report = json.loads(result.read_text()) if result.exists() and result.stat().st_size else None
    noise = [line for line in text.splitlines() if "MonitorBar.qml" in line and any(
        word in line for word in ("TypeError", "ReferenceError", "Unable to assign", "is not a function", "Binding loop"))]
    if not report:
        print(text[-6000:])
        raise SystemExit("The fixture wrote no result.")
    # The compositor's own view: each bar reserves its strip on its own edge.
    for name, position in report["positions"]:
        left, top, right, bottom = reserved.get(name, (0, 0, 0, 0))
        edges = {"left": left, "top": top, "right": right, "bottom": bottom}
        expected = {edge: report["thickness"][name] if edge == position else 0 for edge in edges}
        if edges != expected:
            report["failures"].append(f"{name} reserves {edges}, not {expected}")
        bars = [layer for level in layers.get(name, {}).get("levels", {}).values() for layer in level
                if layer["namespace"] == "omarchy-bar"]
        if len(bars) != 1:
            report["failures"].append(f"{name} has {len(bars)} bar surfaces")
    if len(report["positions"]) == 2 and not report["failures"]:
        report["passed"].append("each bar reserves only its own strip")
    for name in report["passed"]:
        print("ok -", name)
    for failure in report["failures"]:
        print("FAIL -", failure)
    for line in noise:
        print("FAIL - runtime error:", line)
    raise SystemExit(1 if report["failures"] or noise or not report["passed"] else 0)
