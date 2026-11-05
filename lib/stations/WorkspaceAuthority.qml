import QtQuick
import Quickshell.Io
import "../platform/Hypr.js" as Hypr

// Keeps Omarchy from renumbering Station's workspaces. Omarchy reconciles workspaces
// into per-monitor blocks of ten on every reload and hotplug, so a station's workspace
// on the second monitor becomes 11, which is station 6. The reload that does this runs
// the reconcile before any shell event arrives, so only Lua loaded with the
// configuration can stop it: a file in Omarchy's toggle directory, which loads after
// its defaults. Removal cleanup deletes the file and reloads.
Item {
  id: root
  property string path: ""
  property var evalLua: null
  readonly property string source: "-- Managed by the Station plugin; removed with it.\n" + Hypr.workspaceAuthority() + "\n"

  function claim() {
    evalLua(Hypr.workspaceAuthority())
    file.reload()
  }

  FileView {
    id: file
    path: root.path
    atomicWrites: true
    printErrors: false
    onLoaded: if (text() !== root.source) setText(root.source)
    onLoadFailed: setText(root.source)
  }
}
