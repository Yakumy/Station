"""What the rendered harnesses and the compile check share: the live Wayland socket."""
from pathlib import Path
import os
import socket


def require(what):
    """Stop with a plain message when the session's Wayland socket cannot be reached."""
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
        raise SystemExit(f"{what} needs access to the Wayland socket ({error}); run it with session access.")
