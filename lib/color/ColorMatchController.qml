import QtQuick
import Quickshell.Io
import "ColorMatch.js" as ColorMatch
import "../displays/Model.js" as Model
import "../platform/Transactions.js" as Transactions

// Persistent owner of Color Match: per-monitor settings, the ICC profiles they
// become, and Station's toggle file that loads them after monitors.lua. Service
// owns the queue and the configuration; these finite ports never reach it.
Item {
  id: root
  property var monitors: []
  property var settings: ({})
  property bool started: false
  // A reset reloads Hyprland, which would cancel a display preview or migration.
  property string operationState: "idle"
  property string togglePath: ""
  property string profileDir: ""
  property var enqueue: null
  property var publishSettings: null
  property var saveSettings: null

  property bool busy: false
  property string error: ""
  property string fileSource: ""
  property bool fileLoaded: false

  // Connected outputs with the identity their settings are stored under.
  readonly property var displays: {
    // The same identities the rest of Station stores lanes under.
    var all = monitors || [], ids = Model.identities(all), out = []
    all.forEach(function(m, i) {
      if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(String(m.name || ""))) return
      var preset = String(m.colorManagementPreset || "")
      out.push({ name: String(m.name), identity: ids[i], hdr: preset === "hdr" || preset === "hdredid" })
    })
    return out
  }
  // Detached values for the panel, by connector.
  readonly property var snapshot: {
    var values = {}, hdr = []
    displays.forEach(function(display) {
      values[display.name] = ColorMatch.clean(root.settings ? root.settings[display.identity] : null)
      if (display.hdr) hdr.push(display.name)
    })
    return { busy: busy, error: error, values: values, hdr: hdr }
  }

  onFileLoadedChanged: Qt.callLater(reconcile)

  function displayNamed(name) {
    return displays.find(function(display) { return display.name === name }) || null
  }

  function setValue(name, key, value) {
    if (busy) return "busy"
    if (ColorMatch.KEYS.indexOf(key) === -1 || typeof value !== "number" || !isFinite(value)) return "invalid"
    var display = displayNamed(name)
    if (!display) return "invalid"
    if (display.hdr) return "hdr"
    var current = ColorMatch.clean(settings ? settings[display.identity] : null)
    var change = {}
    change[key] = value
    return update(display, ColorMatch.clean(Object.assign({}, current, change)))
  }

  function reset(name) {
    if (busy) return "busy"
    var display = displayNamed(name)
    if (!display) return "invalid"
    return update(display, null)
  }

  function update(display, values) {
    if (!started || !fileLoaded || operationState !== "idle") return "busy"
    var next = Object.assign({}, settings || {})
    if (values && !ColorMatch.isNeutral(values)) next[display.identity] = values
    else delete next[display.identity]
    next = ColorMatch.cleanAll(next)
    var previous = settings
    publishSettings(next)
    if (!write(next, function(ok) {
      if (ok) saveSettings()
      else publishSettings(previous)
    })) return "invalid"
    return "ok"
  }

  // Startup, reload and hotplug: bring the file to the saved settings. A file that
  // already matches costs nothing, so a reload never loops.
  function reconcile() {
    if (!started || !fileLoaded || busy || operationState !== "idle" || !displays.length) return
    write(settings, null)
  }

  function write(values, done) {
    var before = ColorMatch.rows(fileSource)
    var after
    try { after = ColorMatch.desired(values, displays, before) }
    catch (failure) { error = String(failure); if (done) done(false); return false }
    var text = ColorMatch.source(profileDir, after)
    if (text === fileSource) { if (done) done(true); return true }
    var plan = ColorMatch.change(before, after, displays.map(function(display) { return display.name }))
    var lua = plan.rows.map(function(row) { return ColorMatch.rule(row.name, profileDir, row.file) }).join("; ")
    var argv = ["sh", "-c", Transactions.colorMatch, "sh", togglePath, profileDir, fileSource, text, plan.action, lua]
    displays.forEach(function(display) {
      var row = ColorMatch.plan(values, [display])[0]
      if (row) argv.push(row.file, row.base64)
    })
    busy = true
    enqueue(argv, function(code, output) {
      // Record what was written at once: the reload a reset causes reconciles
      // before the file watch would report it.
      if (code === 0) root.fileSource = text
      else toggleFile.reload()
      root.busy = false
      root.error = code === 0 ? "" : code === 4 ? "The color file changed while saving; try again."
        : "Could not apply the color profile: " + String(output || "").trim()
      if (done) done(code === 0)
    })
    return true
  }

  FileView {
    id: toggleFile
    path: root.togglePath
    watchChanges: true
    printErrors: false
    onLoaded: { root.fileSource = text(); root.fileLoaded = true }
    onLoadFailed: { root.fileSource = ""; root.fileLoaded = true }
    onFileChanged: reload()
  }
}
