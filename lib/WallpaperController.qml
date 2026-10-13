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
  readonly property var resolved: Wallpaper.resolve(preferences, themeKey, themePath, themeRevision)
  readonly property var applied: secureStoredScene(resolved)
  property var draft: Wallpaper.resolve({}, "", "", "")
  property bool dirty: false
  property bool busy: false
  property string notice: ""
  property bool noticeError: false
  property var pending: null
  property bool pendingSave: false
  property var previousPreferences: null
  property bool repairPending: false
  property var repairPrevious: null
  property string repairLegacyKey: ""
  property bool importBusy: false
  property string failedLegacyKey: ""
  property int serial: 0
  property string pickerTarget: ""
  readonly property bool pickerBusy: picker.running || pickerDelay.running || importBusy
  onAppliedChanged: {
    if (!dirty && !busy && !importBusy) reset()
    Qt.callLater(prepareLegacyWallpaper)
  }
  onThemeTokenChanged: {
    // A theme switch wins over an in-flight Apply only while following it.
    if (busy && pending && !pendingSave && pending.scene.followTheme) {
      serial++; busy = false; pending = null
      showNotice("Wallpaper changed with Omarchy. Review your selection and apply again.")
    }
    if (draft.followTheme) {
      var next = dirty ? JSON.parse(JSON.stringify(draft)) : JSON.parse(JSON.stringify(applied))
      next.source = themePath
      next.revision = themeRevision
      draft = next
      if (dirty) showNotice("Omarchy's wallpaper changed. Your crop edits are still here.")
    }
  }

  function showNotice(message, error) { notice = message; noticeError = error === true }
  function secureStoredScene(scene) {
    var next = JSON.parse(JSON.stringify(scene))
    if (next.followTheme) return next
    var prefix = station.stateDir + "/wallpapers/"
    var paths = [next.source]
    Object.keys(next.perDisplay).forEach(function(key) { paths.push(next.perDisplay[key]) })
    next.safe = next.safe && paths.every(function(path) { return path.indexOf(prefix) === 0 })
    return next
  }
  function clearNotice() { notice = ""; noticeError = false }
  function reset() { draft = JSON.parse(JSON.stringify(applied)); dirty = false; clearNotice() }
  function preferenceSaved() {
    if (repairPending) {
      repairPending = false; repairPrevious = null; repairLegacyKey = ""
      importBusy = false; failedLegacyKey = ""
      reset(); showNotice("Saved wallpaper prepared safely.")
      return
    }
    if (!pendingSave) return
    pendingSave = false; pending = null; busy = false; dirty = false
    reset(); showNotice("Wallpaper applied.")
  }
  function preferenceFailed() {
    if (repairPending) {
      repairPending = false; importBusy = false
      failedLegacyKey = repairLegacyKey; repairLegacyKey = ""
      station.config = Object.assign({}, station.config, {wallpaper: repairPrevious})
      repairPrevious = null
      showNotice("Could not safely prepare the saved wallpaper. Choose it again.", true)
      return
    }
    if (!pendingSave) return
    pendingSave = false; pending = null; busy = false
    station.config = Object.assign({}, station.config, {wallpaper: previousPreferences})
    showNotice("Could not save preferences. Your previous wallpaper has been restored.", true)
  }
  function change(key, value) {
    if (busy || importBusy) return
    var next = JSON.parse(JSON.stringify(draft))
    next[key] = value
    draft = next; dirty = true; clearNotice()
  }
  function frame(value) { change("framing", Wallpaper.framing(value)) }
  function sanitizedPath(output) {
    var path = String(output || "").replace(/\n$/, "")
    var prefix = station.stateDir + "/wallpapers/"
    return Wallpaper.path(path) && path.indexOf(prefix) === 0 ? path : ""
  }
  function stagePath(path, generation, index, done) {
    if (!Wallpaper.path(path) || !station.pluginDir) { done(1, ""); return }
    var folder = station.stateDir + "/wallpapers/import-" + Date.now() + "-" + generation + "-" + index
    station.enqueue(["perl", station.pluginDir + "/lib/SanitizeWallpaper.pl", path, folder], function(code, output) {
      var prepared = code === 0 ? sanitizedPath(output) : ""
      done(prepared ? 0 : 1, prepared)
    })
  }
  function stagePaths(paths, generation, done, index, results) {
    index = index || 0; results = results || ({})
    if (generation !== serial) { done(1, results); return }
    if (index >= paths.length) { done(0, results); return }
    stagePath(paths[index], generation, index, function(code, prepared) {
      if (generation !== root.serial || code !== 0) { done(1, results); return }
      results[paths[index]] = prepared
      root.stagePaths(paths, generation, done, index + 1, results)
    })
  }
  function acceptSanitized(path, target) {
    if (draft.followTheme) {
      showNotice("Turn off Follow Omarchy wallpaper to select your own wallpaper.", true)
      return
    }
    if (!sanitizedPath(path)) { showNotice("Choose a local image file.", true); return }
    if (target) {
      var map = Object.assign({}, draft.perDisplay); map[target] = path
      change("perDisplay", map)
    } else { change("source", path); frame({}) }
    change("safe", true)
  }
  function prepareSelection(path) {
    if (!Wallpaper.path(path)) { showNotice("Choose a local image file.", true); return }
    var target = pickerTarget
    var generation = ++serial
    importBusy = true; showNotice("Preparing wallpaper safely…")
    stagePath(path, generation, 0, function(code, prepared) {
      if (generation !== root.serial) return
      root.importBusy = false
      if (code !== 0) { root.showNotice("The image could not be prepared safely. Choose another file.", true); return }
      root.acceptSanitized(prepared, target)
    })
  }
  function prepareLegacyWallpaper() {
    if (!station.configLoaded || !station.pluginDir || dirty || busy || importBusy
        || applied.followTheme || applied.safe || !applied.source) return
    var paths = [applied.source]
    Object.keys(applied.perDisplay).forEach(function(key) {
      if (paths.indexOf(applied.perDisplay[key]) < 0) paths.push(applied.perDisplay[key])
    })
    var key = JSON.stringify(paths)
    if (key === failedLegacyKey) return
    var generation = ++serial
    importBusy = true; showNotice("Preparing saved wallpaper safely…")
    stagePaths(paths, generation, function(code, prepared) {
      if (generation !== root.serial) return
      if (code !== 0) {
        root.importBusy = false; root.failedLegacyKey = key
        root.showNotice("Could not safely prepare the saved wallpaper. Choose it again.", true)
        return
      }
      var scene = JSON.parse(JSON.stringify(root.applied))
      scene.source = prepared[scene.source]
      Object.keys(scene.perDisplay).forEach(function(identity) {
        scene.perDisplay[identity] = prepared[scene.perDisplay[identity]]
      })
      scene.safe = true
      var settings = Wallpaper.settings(root.preferences)
      settings.pinned = Wallpaper.profile(scene)
      root.repairPrevious = root.station.config.wallpaper
      root.repairLegacyKey = key
      root.repairPending = true
      root.station.config = Object.assign({}, root.station.config, {wallpaper: Wallpaper.settings(settings)})
      root.station.saveConfig()
    })
  }
  function choose(identity) {
    if (pickerBusy || busy) return false
    if (draft.followTheme) {
      showNotice("Turn off Follow Omarchy wallpaper to select your own wallpaper.", true)
      return false
    }
    pickerTarget = identity || ""
    // The picker is a separate native window: release the panel's focus grab.
    station.panelWanted = false
    pickerDelay.restart()
    return true
  }
  function useTheme() {
    change("source", themePath); change("perDisplay", {}); change("safe", true); frame({})
  }
  function apply() {
    if (busy || importBusy || !dirty || !layout.displays.length) return
    var scene = JSON.parse(JSON.stringify(draft))
    var paths = [scene.source]
    if (scene.mode === "individual") Object.keys(scene.perDisplay).forEach(function(key) {
      if (paths.indexOf(scene.perDisplay[key]) < 0) paths.push(scene.perDisplay[key])
    })
    if (paths.some(function(p) { return !Wallpaper.path(p) })) { showNotice("Choose a local wallpaper first.", true); return }
    if (!scene.safe) { showNotice("Choose the wallpaper again so it can be prepared safely.", true); return }
    serial++; busy = true; showNotice("Checking wallpaper…")
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
        busy = false; pending = null; showNotice("An image could not be opened. Choose another file.", true); return
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
      if (code !== 0) { root.busy = false; root.showNotice("Could not save the wallpaper. Your previous wallpaper is unchanged.", true); root.pending = null; return }
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
      if (code === 0) root.prepareSelection(result)
      else if (code !== 1) root.showNotice("The desktop file picker could not open.", true)
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
