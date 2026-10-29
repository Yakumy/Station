"""Read-only live feed + offscreen bar geometry smoke test; no workspace actions."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-open-apps-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
    (root / "Station").symlink_to(repo / "lib")
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import "Station" as Station
ShellRoot {
  Station.OpenAppsController { id: feed }
  QtObject {
    id: host
    property bool foregroundAnimationEnabled: false
    property bool vertical: false
    property int barSize: 32
    property string position: "top"
    property string fontFamily: "sans-serif"
    property color barForeground: "white"
    property color urgent: "red"
    function hideTooltip(item) {}
  }
  Station.StationBar {
    id: bar
    bar: host
    apps: [{ address: "a", appId: "dev.zed.Zed", initialAppId: "", title: "A", focused: true },
           { address: "b", appId: "missing-app-for-fallback", initialAppId: "", title: "B", focused: false }]
  }
  Timer {
    interval: 1500; running: true
    onTriggered: {
      if (!Object.keys(feed.rows).length) throw new Error("Live feed did not populate")
      if (bar.width <= 0 || bar.height <= 0) throw new Error("Empty horizontal bar")
      console.log("OPEN_APPS_FEED", JSON.stringify(Object.keys(feed.rows).map(function(name) {
        return { monitor: name, count: feed.rows[name].length,
          focused: feed.rows[name].filter(function(row) { return row.focused }).length }
      })))
      host.vertical = true
      finish.start()
    }
  }
  Timer {
    id: finish; interval: 100
    onTriggered: {
      if (bar.height <= bar.width) throw new Error("Icons did not stack vertically")
      feed.active = false
      if (Object.keys(feed.rows).length) throw new Error("Disabling did not clear rows")
      console.log("OPEN_APPS_SMOKE_PASSED")
      Qt.quit()
    }
  }
}
''')
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="offscreen"),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=10)
    print(result.stdout)
    assert "OPEN_APPS_SMOKE_PASSED" in result.stdout
    assert not any(error in result.stdout for error in ("TypeError", "ReferenceError", "Error:", "Unable to assign"))
