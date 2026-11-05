"""Production Display + Workspace owners and root barrier, with fake I/O/effects.

The composition, projections and selected root functions come from Service.qml.
No production Service, desktop process, user path or live compositor is used.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
service = (repo / "Service.qml").read_text()
owner = (repo / "lib/DisplayController.qml").read_text()
others = "\n".join((repo / "lib" / f"{name}.qml").read_text()
    for name in ("PanelIntent", "StationController", "CompositorLane"))
# The session is flat: route owner ids back to its own functions and stubs.
flatten = lambda text: re.sub(r"\b(stations|compositor|store|keybindings|barLayers|leases|screenRecovery|windowSettings|panel)\.", "root.", text)
functions = {m[1]: m[0] for m in re.finditer(
    r"^  function (\w+)\([^\n]*\{\n[\s\S]*?^  \}", others + "\n" + service, re.M)}
forwarders = re.findall(r"^  function \w+\([^\n]*\{ return displayController\.[^\n]*\}$", service, re.M)
selected = ["begin", "handleSnapshotFailure", "targetMapping", "monitorSignature", "eventExpected",
    "handleEvent", "completeSnapshot", "applyRuntime", "updateAssignments", "clearPanelEvacuation",
    "requestPanelEvacuation", "acknowledgePanelEvacuation", "swapRole", "readyForWindows", "observeDesktop"]
composition = "\n".join(re.search(r"^  Station\." + name + r" \{\n[\s\S]*?^  \}",
    service, re.M)[0] for name in ("WorkspaceController", "DisplayController"))
projections = "\n".join(line for line in service.splitlines()
    if line.startswith("  readonly property ") and (": displayController." in line
        or re.search(r"property \w+ (workspaceData|workspaceMap):", line)))
projections += "\n" + "\n".join(f"  readonly property var {name}: {source}.{name}" for source, names in {
    "workspace": ("mappingLoaded", "migrationPhase", "topologyDirty", "migrationAttempts"),
    "displayController": ("previewFound", "previewLoaded", "monitorsLoaded", "monitorsSource", "keepDisableToggle",
        "layoutWriteKind", "keepOptions", "pendingDisplayConfig", "draftMirrorSource", "previewBefore"),
    }.items() for name in names)
barrier_timer = re.search(r"^  Timer \{\n    id: panelEvacuationTimeout\n[\s\S]*?^  \}", others, re.M)[0]
barrier_timer = barrier_timer.replace("root.timedOut(root.panelEvacuationPurpose, root.panelEvacuationFrom)", "root.panelEvacuationTimedOut()")

with tempfile.TemporaryDirectory(prefix="station-display-owner-") as folder:
    root = Path(folder)
    probe = root / "Probe"
    probe.mkdir()
    for name in ("DisplayController.qml", "WorkspaceController.qml", "Model.js", "Grid.js",
                 "Hypr.js", "MonitorsLua.js", "Transactions.js", "Events.js", "Store.js"):
        (probe / name).write_text((repo / "lib" / name).read_text())
    io = root / "Quickshell/Io"
    io.mkdir(parents=True)
    (root / "Quickshell/qmldir").write_text("module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    (root / "Quickshell/Quickshell.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var launches: []
  function execDetached(args) { launches.push(args) }
  function env(name) { return "/isolated" }
}
''')
    (io / "qmldir").write_text("module Quickshell.Io\nFileView 1.0 FileView.qml\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n")
    (io / "FileView.qml").write_text('''import QtQuick
Item {
  property string path: ""
  property bool watchChanges: false
  property bool atomicWrites: false
  property bool printErrors: false
  property string readText: ""
  property var writes: []
  property int pendingWrites: 0
  property int reloads: 0
  signal loaded()
  signal loadFailed()
  signal fileChanged()
  signal saved()
  signal saveFailed()
  function text() { return readText }
  function setText(value) {
    if (readText === value) return
    readText=value; writes.push(value); pendingWrites++
  }
  function reload() { reloads++; loaded() }
  function ack() { if (pendingWrites) { pendingWrites--; saved() } }
  function fail() { if (pendingWrites) { pendingWrites--; saveFailed() } }
}
''')
    (io / "Process.qml").write_text('''import QtQuick
Item {
  property var command: []
  property bool running: false
  property var stdout: null
  property var stderr: null
  signal exited(int code)
  function finish(code) { running=false; exited(code) }
}
''')
    (io / "StdioCollector.qml").write_text('''import QtQuick
QtObject {
  property bool waitForEnd: false
  property string text: ""
  signal streamFinished()
}
''')
    session = (repo / "tools/v2/fixtures/DisplaySession.qml").read_text()
    session = session.replace("// INSERT_COMPOSITION", flatten(composition)).replace("// INSERT_PROJECTIONS", projections)
    session = session.replace("// INSERT_ROOT_FUNCTIONS", flatten("\n\n".join([functions[n] for n in selected] + forwarders)))
    session = session.replace("// INSERT_BARRIER_TIMER", barrier_timer)
    (root / "DisplaySession.qml").write_text(session)
    (root / "tst_display.qml").write_text((repo / "tools/v2/fixtures/tst-display-owner.qml").read_text())
    result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-import", str(root), "-input", str(root)],
        env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME=""),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
    print(result.stdout)
    raise SystemExit(result.returncode)
