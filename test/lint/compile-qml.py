"""Discover and compile runtime QML against installed qs.Ui, without installing it.

--list needs no desktop/session. Compilation needs Wayland (KeyboardPanel cannot
compile offscreen). Production Panel/Service/Bar objects are never instantiated.
"""
from pathlib import Path, PurePosixPath
import argparse
import json
import os
import socket
import subprocess
import tempfile


def entry_path(root, value):
    """Reject escaping or symlinked manifest paths before loading any QML."""
    if (not isinstance(value, str) or not value
            or "\\" in value or any(ord(c) < 32 for c in value)
            or any(part in ("", ".", "..") for part in value.split("/"))
            or PurePosixPath(value).is_absolute()):
        raise ValueError(f"Unsafe QML entry point: {value!r}")
    path = root / value
    reject_symlinks(root, path)
    if path.suffix != ".qml" or not path.is_file():
        raise ValueError(f"Missing or non-QML entry point: {value}")
    return path


def reject_symlinks(root, path):
    for part in (path, *path.parents):
        if part == root:
            break
        if part.is_symlink():
            raise ValueError(f"Refusing symlink: {part}")


def discover_components(root):
    """Manifest entries, all root QML, and recursive library/entry subtrees.

    Exclude tools, documentation and artwork unless the manifest explicitly
    declares an entry there. Do not follow symlinks into another source tree.
    """
    root = Path(root).resolve()
    manifest_path = root / "manifest.json"
    reject_symlinks(root, manifest_path)
    manifest = json.loads(manifest_path.read_text())
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be an object")
    entries = manifest.get("entryPoints")
    if not isinstance(entries, dict) or not entries:
        raise ValueError("manifest.entryPoints must be a nonempty object")
    for kind, key in {"service": "service", "bar-widget": "barWidget", "bar": "bar"}.items():
        if kind in manifest.get("kinds", []) and key not in entries:
            raise ValueError(f"Missing declared entry point: {key}")
    paths = {entry_path(root, value) for value in entries.values()}
    directories = {root / "lib"}
    for path in paths:
        if path.parent != root:
            directories.add(root / path.relative_to(root).parts[0])
    for path in root.glob("*.qml"):
        reject_symlinks(root, path)
        if not path.is_file():
            raise ValueError(f"Not a QML file: {path}")
        paths.add(path)
    for directory in sorted(directories):
        reject_symlinks(root, directory)
        if not directory.exists():
            continue
        if not directory.is_dir():
            raise ValueError(f"Not a runtime directory: {directory}")
        def unreadable(error):
            raise error  # os.walk otherwise silently skips unreadable subtrees.
        for current, folders, files in os.walk(directory, followlinks=False, onerror=unreadable):
            for name in folders + files:
                path = Path(current) / name
                reject_symlinks(root, path)
                if path.suffix == ".qml" and path.is_file():
                    paths.add(path)
    return sorted(path.relative_to(root).as_posix() for path in paths)


def compile_components(fixture, component_names):
    label = "STATION" if json.loads((fixture / "manifest.json").read_text()).get("id") == "yakumy.station" else "M0"
    display = os.environ.get("WAYLAND_DISPLAY", "")
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    address = Path(display) if display else None
    if address and not address.is_absolute():
        address = Path(runtime) / address if runtime else None
    try:
        if address is None:
            raise OSError("WAYLAND_DISPLAY or XDG_RUNTIME_DIR is unset")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(1)
            connection.connect(str(address))
    except OSError as error:
        raise SystemExit(f"QML check needs access to the Wayland socket ({error}); run it with session access.")
    print(f"QML compile targets ({len(component_names)}): " + ", ".join(component_names), flush=True)
    with tempfile.TemporaryDirectory(prefix="station-qml-") as directory:
        root = Path(directory)
        for name in ("Commons", "Ui"):
            (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name,
                                    target_is_directory=True)
        (root / "Probe").symlink_to(fixture, target_is_directory=True)
        # JSON serializes filenames as QML string literals; no filename is code.
        (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
  Component.onCompleted: {
    for (var name of ''' + json.dumps(component_names) + ''') {
      var c = Qt.createComponent("Probe/" + name)
      if (c.status !== Component.Ready) {
        console.error("''' + label + '''_COMPILE_FAILED " + c.errorString())
        continue
      }
    }
    console.log("''' + label + '''_COMPONENTS_READY")
  }
}
''')
        process = subprocess.Popen(["quickshell", "--no-color", "-p", str(root)],
                                   env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            try:
                output, _ = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                output, _ = process.communicate(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
        print(output)
        if f"{label}_COMPONENTS_READY" not in output or f"{label}_COMPILE_FAILED" in output:
            raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", nargs="?", type=Path,
                        default=Path(__file__).resolve().parent / "m0-plugin")
    parser.add_argument("--list", action="store_true", help="List discovered QML as JSON without Wayland or compilation")
    args = parser.parse_args()
    fixture = args.fixture.resolve()
    try:
        components = discover_components(fixture)
    except (OSError, ValueError) as error:
        raise SystemExit(f"QML discovery failed: {error}")
    if args.list:
        print(json.dumps(components))
    else:
        compile_components(fixture, components)


if __name__ == "__main__":
    main()
