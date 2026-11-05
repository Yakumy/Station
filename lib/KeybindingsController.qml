import QtQuick
import Quickshell
import Quickshell.Io
import "Binds.js" as Binds

// Owns the keybinding conflict check and runtime application, once per
// configuration generation. `omarchy menu keybindings --print` is the conflict
// identity; `hyprctl binds -j` cannot identify Lua `code:` keys.
Item {
  id: root
  property bool started: false
  property int configGeneration: 0
  property var config: ({})
  property var persisted: ({})
  property var updateConfig: null
  property var saveState: null
  property var evalLua: null

  property int appliedGeneration: -1
  property var bindStatuses: []
  property int bindProbeGeneration: -1
  property string menuBindingsText: ""
  property bool menuBindingsOk: false
  property string hyprBindingsText: ""
  property string personalBindingsText: ""

  function invalidate() { appliedGeneration = -1 }

  function applyBinds() {
    if (!started || appliedGeneration === configGeneration || keybindings.running || hyprBindSnapshot.running) return
    bindProbeGeneration = configGeneration
    keybindings.running = true
  }

  function finishBindCheck() {
    if (bindProbeGeneration !== configGeneration) { Qt.callLater(applyBinds); return }
    var definitions = Binds.effectiveDefinitions(config.keybindings)
    var fallback = Binds.parseHypr(hyprBindingsText).concat(Binds.parseLua(personalBindingsText))
    var accepted = []
    var statuses = []
    for (var i = 0; i < definitions.length; i++) {
      var definition = definitions[i]
      var status = Binds.classify(definition.combo, { ok: menuBindingsOk, text: menuBindingsText }, fallback)
      var approved = config.approvedReplacements.indexOf(Binds.normalize(definition.combo)) !== -1
      if (status.status === "conflict" && approved) status = { status: "replacement", owners: status.owners }
      statuses.push({ combo: definition.combo, label: definition.label,
        id: definition.id, status: status.status, owners: status.owners })
      if (status.status !== "conflict") {
        var copy = Object.assign({}, definition)
        if (approved) copy.replacement = true
        accepted.push(copy)
      }
    }
    bindStatuses = statuses
    var lua = Binds.applyLua(accepted, persisted.appliedBinds.filter(function(combo) {
      return !statuses.some(function(row) { return Binds.normalize(row.combo) === Binds.normalize(combo) && row.status === "conflict" })
    }))
    evalLua(lua, function(code) {
      if (code === 0) {
        root.persisted.appliedBinds = accepted.map(function(item) { return item.combo })
        root.appliedGeneration = root.configGeneration
        root.saveState()
      }
    })
  }

  function approveBinding(combo) {
    var normalized = Binds.normalize(combo)
    if (!Binds.validCombo(normalized)) return "invalid"
    updateConfig({ approvedReplacements: config.approvedReplacements.indexOf(normalized) === -1
      ? config.approvedReplacements.concat([normalized]) : config.approvedReplacements })
    appliedGeneration = -1
    applyBinds()
    return "ok"
  }

  function setBinding(id, combo) {
    var known = Binds.definitions().some(function(definition) { return definition.id === id })
    var normalized = Binds.normalize(combo)
    if (!known || !Binds.validCombo(normalized)) return "invalid"
    var custom = Object.assign({}, config.keybindings)
    custom[id] = normalized.replace(/\+/g, " + ")
    updateConfig({ keybindings: custom,
      approvedReplacements: config.approvedReplacements.filter(function(value) { return value !== normalized }) })
    appliedGeneration = -1
    applyBinds()
    return "ok"
  }

  FileView {
    id: personalBindings
    path: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
    watchChanges: true
    printErrors: false
    onLoaded: { root.personalBindingsText = text(); root.appliedGeneration = -1; root.applyBinds() }
    onLoadFailed: root.personalBindingsText = ""
    onFileChanged: reload()
  }

  Process {
    id: keybindings
    command: ["omarchy", "menu", "keybindings", "--print"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: keybindings.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: function(code) {
      root.menuBindingsText = captured
      root.menuBindingsOk = code === 0 && captured.trim() !== ""
      hyprBindSnapshot.running = true
    }
  }

  Process {
    id: hyprBindSnapshot
    command: ["hyprctl", "binds", "-j"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: hyprBindSnapshot.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: { root.hyprBindingsText = captured; root.finishBindCheck() }
  }
}
