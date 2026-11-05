import QtQuick
import Quickshell
import Quickshell.Io
import "Store.js" as Store

// Owns config.json (preferences) and state.json (runtime bookkeeping): their
// load gates, atomic writes and directory creation. Other owners change fields
// through the Service and save here; Store.js holds the versioned codec.
Item {
  id: root
  property var loaded: null
  property var directoriesReady: null
  property var configSaved: null
  property var configSaveFailed: null

  property var config: Store.configDefaults()
  property var persisted: Store.stateDefaults()
  property bool configLoaded: false
  property bool stateLoaded: false
  property bool dirsReady: false

  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/station"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/station"
  readonly property string configPath: configDir + "/config.json"
  readonly property string statePath: stateDir + "/state.json"

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }

  function prepare() { ensureDirs.running = true }

  function saveConfig() {
    if (configLoaded && dirsReady) configFile.setText(JSON.stringify(config, null, 2) + "\n")
  }

  function saveState() {
    if (stateLoaded && dirsReady) stateFile.setText(JSON.stringify(persisted, null, 2) + "\n")
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    printErrors: false
    onLoaded: { if (!root.configLoaded) { root.config = Store.loadConfig(root.parseJson(text(), {})); root.configLoaded = true; root.loaded() } }
    onLoadFailed: { if (!root.configLoaded) { root.config = Store.configDefaults(); root.configLoaded = true; root.loaded() } }
    onSaved: root.configSaved()
    onSaveFailed: root.configSaveFailed()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: { if (!root.stateLoaded) { root.persisted = Store.loadState(root.parseJson(text(), {})); root.stateLoaded = true; root.loaded() } }
    onLoadFailed: { if (!root.stateLoaded) { root.persisted = Store.stateDefaults(); root.stateLoaded = true; root.loaded() } }
  }

  Process {
    id: ensureDirs
    command: ["mkdir", "-p", root.configDir, root.stateDir]
    onExited: {
      root.dirsReady = true
      configFile.reload()
      stateFile.reload()
      root.directoriesReady()
    }
  }
}
