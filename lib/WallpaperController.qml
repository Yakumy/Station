import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui as Ui
import qs.Commons
import "Wallpaper.js" as Wallpaper
import "Model.js" as Model
import "." as Station

Item {
  id: root
  required property var station
  readonly property var layout: Wallpaper.topology(station.monitors, Model.identities(station.monitors))
  readonly property var preferences: Wallpaper.settings(station.config.wallpaper)
  property string themePath: ""
  property string themeName: ""
  property string themeRevision: ""
  readonly property string themeKey: JSON.stringify([themeName, themePath])
  readonly property string themeToken: JSON.stringify([themeName, themePath, themeRevision])
  readonly property var applied: Wallpaper.resolve(preferences, themeKey, themePath, themeRevision)
  property var draft: Wallpaper.resolve({}, "", "", "")
  property bool dirty: false
  property bool busy: false
  property string notice: ""
  property var pending: null
  property bool pendingSave: false
  property var previousPreferences: null
  property int serial: 0
  property string pickerTarget: ""
  readonly property bool pickerBusy: picker.running || pickerDelay.running
  onAppliedChanged: if (!dirty && !busy) reset()
  onThemeTokenChanged: {
    // A theme switch wins over an in-flight Apply only while following it.
    if (busy && pending && !pendingSave && pending.scene.followTheme) {
      serial++; busy = false; pending = null
      notice = "Wallpaper changed with Omarchy. Review your selection and apply again."
    }
    if (draft.followTheme) {
      var next = dirty ? JSON.parse(JSON.stringify(draft)) : JSON.parse(JSON.stringify(applied))
      next.source = themePath
      next.revision = themeRevision
      draft = next
      if (dirty) notice = "Omarchy's wallpaper changed. Your crop edits are still here."
    }
  }

  function reset() { draft = JSON.parse(JSON.stringify(applied)); dirty = false; notice = "" }
  function preferenceSaved() {
    if (!pendingSave) return
    pendingSave = false; pending = null; busy = false; dirty = false
    reset(); notice = "Wallpaper applied."
  }
  function preferenceFailed() {
    if (!pendingSave) return
    pendingSave = false; pending = null; busy = false
    station.config = Object.assign({}, station.config, {wallpaper: previousPreferences})
    notice = "Could not save preferences. Your previous wallpaper has been restored."
  }
  function change(key, value) {
    if (busy) return
    var next = JSON.parse(JSON.stringify(draft))
    next[key] = value
    draft = next; dirty = true; notice = ""
  }
  function frame(value) { change("framing", Wallpaper.framing(value)) }
  function select(path) {
    if (!Wallpaper.path(path)) { notice = "Choose a local image file."; return }
    if (pickerTarget) {
      var map = Object.assign({}, draft.perDisplay); map[pickerTarget] = path
      change("perDisplay", map)
    } else { change("source", path); frame({}) }
  }
  function choose(identity) {
    if (pickerBusy || busy) return
    pickerTarget = identity || ""
    // The picker is a separate native window: release the panel's focus grab.
    station.panelWanted = false
    pickerDelay.restart()
  }
  function useTheme() {
    change("source", themePath); change("perDisplay", {}); frame({})
  }
  function apply() {
    if (busy || !dirty || !layout.displays.length) return
    var scene = JSON.parse(JSON.stringify(draft))
    var paths = [scene.source]
    if (scene.mode === "individual") Object.keys(scene.perDisplay).forEach(function(key) {
      if (paths.indexOf(scene.perDisplay[key]) < 0) paths.push(scene.perDisplay[key])
    })
    if (paths.some(function(p) { return !Wallpaper.path(p) })) { notice = "Choose a local wallpaper first."; return }
    serial++; busy = true; notice = "Checking wallpaper…"
    pending = { scene: scene, paths: paths, key: themeKey, serial: serial }
    validation.model = paths
    Qt.callLater(checkImages)
  }
  function checkImages() {
    if (!busy || !pending || validation.count !== pending.paths.length) return
    for (var i = 0; i < validation.count; i++) {
      var img = validation.objectAt(i)
      if (!img || img.status === Image.Loading || img.status === Image.Null) return
      if (img.status === Image.Error) {
        busy = false; pending = null; notice = "An image could not be opened. Choose another file."; return
      }
    }
    if (pending.copying) return
    pending.copying = true
    var job = pending, folder = station.stateDir + "/wallpapers/" + Date.now() + "-" + job.serial
    var destinations = job.paths.map(function(p, i) { return folder + "/" + i + "." + p.split(".").pop().replace(/[^a-zA-Z0-9]/g, "").slice(0, 10) })
    // Fixed script; every path is a quoted positional argument. Originals and
    // Omarchy's current/background link are never changed. Snapshots survive
    // theme regeneration at the same pathname and deletion of a chosen file.
    var script = 'set -eu; umask 077; folder=$1; shift; mkdir -p -- "${folder%/*}"; mkdir -- "$folder"; while [ "$#" -gt 0 ]; do cp --reflink=auto -- "$1" "$2"; shift 2; done'
    var args = ["bash", "-c", script, "station-wallpaper", folder]
    job.paths.forEach(function(p, i) { args.push(p, destinations[i]) })
    station.enqueue(args, function(code) {
      if (!root.pending || job.serial !== root.serial) return
      if (code !== 0) { root.busy = false; root.notice = "Could not save the wallpaper. Your previous wallpaper is unchanged."; root.pending = null; return }
      var p = Wallpaper.profile(job.scene)
      p.source = destinations[job.paths.indexOf(p.source)]
      Object.keys(p.perDisplay).forEach(function(key) {
        var index = job.paths.indexOf(p.perDisplay[key])
        if (index >= 0) p.perDisplay[key] = destinations[index]
      })
      var settings = Wallpaper.settings(root.preferences)
      settings.mode = job.scene.mode; settings.followTheme = job.scene.followTheme
      settings.pinned = p
      if (settings.followTheme) { delete settings.profiles[job.key]; settings.profiles[job.key] = p }
      root.previousPreferences = root.station.config.wallpaper
      root.pendingSave = true
      root.station.config = Object.assign({}, root.station.config, { wallpaper: Wallpaper.settings(settings) })
      root.station.saveConfig()
    })
  }

  Instantiator {
    id: validation
    model: []
    delegate: Image {
      required property string modelData
      source: Util.fileUrl(modelData)
      asynchronous: true
      onStatusChanged: Qt.callLater(root.checkImages)
    }
  }
  Process {
    id: themeRead
    command: ["bash", "-c", 'readlink -f -- "$1"; cat -- "$2"; stat -Lc "%i:%s:%y" -- "$1"', "station-background",
      Quickshell.env("HOME") + "/.local/state/omarchy/current/background",
      Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.themeName = lines.length > 1 ? lines[1] : ""
        root.themePath = Wallpaper.path(lines[0])
        root.themeRevision = lines.length > 2 ? lines[2] : ""
      }
    }
  }
  Timer { interval: 250; repeat: true; running: root.station.configLoaded; triggeredOnStart: true; onTriggered: if (!themeRead.running) themeRead.running = true }
  Process {
    id: picker
    command: ["omarchy", "file", "select", "--title", "Choose wallpaper", "--extensions", "png jpg jpeg webp bmp gif"]
    property string result: ""
    onStarted: result = ""
    stdout: StdioCollector { onStreamFinished: picker.result = text.replace(/\n$/, "") }
    onExited: function(code) {
      if (code === 0) root.select(result)
      else if (code !== 1) root.notice = "The desktop file picker could not open."
      root.station.rememberedTab = 1
      root.station.panelWanted = true
    }
  }
  Timer { id: pickerDelay; interval: 200; onTriggered: picker.running = true }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: surface
      required property var modelData
      readonly property var display: root.layout.displays.find(function(d) { return d.name === modelData.name }) || null
      readonly property bool stock: root.applied.mode === "same" && root.applied.followTheme && root.applied.source === root.themePath
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "station-wallpaper"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      color: "transparent"
      visible: root.station.configLoaded && display !== null && !stock && wallpaper.status === Image.Ready && !remap.remapping
      Ui.ScreenMoveRemap { id: remap; window: surface }
      Station.WallpaperImage {
        id: wallpaper
        anchors.fill: parent
        scene: root.applied
        layout: root.layout
        display: surface.display || ({ width: 1, height: 1, x: 0, y: 0, identity: "" })
      }
    }
  }
}
