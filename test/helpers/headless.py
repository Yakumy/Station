"""A private nested Hyprland for tests that need a real compositor.

Adapted from Omarchy's test/headless (MIT, see THIRD_PARTY_NOTICES.md). The nested
compositor starts silently on special:station-test of the running session, gets its
own runtime directory and headless outputs, and drops its host-backed output, so no
window stays on the desktop and no input, monitor or configuration there changes.
"""
from pathlib import Path
import json
import os
import shlex
import shutil
import signal
import subprocess
import tempfile
import time

CONFIG = """hl.config({
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
  animations = { enabled = false },
})
"""


def available():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    display = os.environ.get("WAYLAND_DISPLAY", "")
    return bool(display and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
                and Path(runtime, display).exists()
                and all(shutil.which(name) for name in ("Hyprland", "hyprctl", "quickshell")))


class Headless:
    """with Headless(outputs=2) as session: session.run([...], env)"""

    def __init__(self, outputs=1):
        self.outputs = [f"HEADLESS-{i + 1}" for i in range(outputs)]
        self.pid = None
        self.env = None

    def __enter__(self):
        outer = os.environ["XDG_RUNTIME_DIR"]
        # Short, so the event socket's path stays under the 108-byte limit.
        self.directory = Path(tempfile.mkdtemp(prefix="sh.", dir="/tmp"))
        try:
            self._start(outer)
        except BaseException:
            self.__exit__()
            raise
        return self

    def _start(self, outer):
        runtime = self.directory / "rt"
        runtime.mkdir(mode=0o700)
        (self.directory / "hyprland.lua").write_text(CONFIG)
        script = self.directory / "run.sh"
        display = Path(outer, os.environ["WAYLAND_DISPLAY"])
        script.write_text("\n".join([
            "#!/bin/bash",
            f"export XDG_RUNTIME_DIR={shlex.quote(str(runtime))}",
            f"export WAYLAND_DISPLAY={shlex.quote(str(display))}",
            "unset HYPRLAND_INSTANCE_SIGNATURE DISPLAY",
            "export HYPRLAND_NO_CRASHREPORTER=1 HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_RT=1",
            "ulimit -c 0",
            f"echo $$ >{shlex.quote(str(self.directory / 'pid'))}",
            f"exec setsid -w Hyprland -c {shlex.quote(str(self.directory / 'hyprland.lua'))}"
            f" >{shlex.quote(str(self.directory / 'log'))} 2>&1",
            ""]))
        script.chmod(0o700)
        # The path is ours and JSON quoting is valid Lua quoting for it.
        launch = ("hl.dsp.exec_cmd(" + json.dumps(str(script)) + ", { workspace = \"special:station-test silent\","
                  " float = true, no_initial_focus = true, size = \"1920 1080\" })")
        subprocess.run(["hyprctl", "dispatch", launch], check=True, stdout=subprocess.DEVNULL)

        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            signature = next(iter(sorted((runtime / "hypr").iterdir())), None) if (runtime / "hypr").is_dir() else None
            socket = next((p for p in sorted(runtime.glob("wayland-*")) if p.suffix != ".lock"), None)
            if signature and socket:
                self.env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY=socket.name,
                                HYPRLAND_INSTANCE_SIGNATURE=signature.name)
                self.env.pop("DISPLAY", None)
                if self.hyprctl("monitors", check=False) is not None:
                    break
            time.sleep(0.05)
        else:
            raise RuntimeError("nested Hyprland did not become ready")
        for name in self.outputs:
            subprocess.run(["hyprctl", "output", "create", "headless", name], env=self.env, check=True, stdout=subprocess.DEVNULL)
        for monitor in self.hyprctl("monitors"):
            if monitor["name"] not in self.outputs:
                subprocess.run(["hyprctl", "output", "remove", monitor["name"]], env=self.env, check=True, stdout=subprocess.DEVNULL)
        names = sorted(monitor["name"] for monitor in self.hyprctl("monitors"))
        if names != sorted(self.outputs):
            raise RuntimeError(f"unexpected nested outputs: {names}")

    def hyprctl(self, *command, check=True):
        result = subprocess.run(["hyprctl", "-j", *command], env=self.env, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=5)
        try:
            return json.loads(result.stdout)
        except ValueError:
            if check:
                raise
            return None

    def __exit__(self, *_):
        # Every process of the nested session carries its runtime directory.
        marker = f"XDG_RUNTIME_DIR={self.directory / 'rt'}".encode()
        for sig in (signal.SIGTERM, signal.SIGKILL):
            alive = []
            for path in Path("/proc").glob("[0-9]*/environ"):
                try:
                    if marker in path.read_bytes().split(b"\0"):
                        alive.append(int(path.parent.name))
                except OSError:
                    continue
            for pid in alive:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
            if not alive:
                break
            time.sleep(0.6)
        shutil.rmtree(self.directory, ignore_errors=True)
