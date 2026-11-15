import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui as Ui
import qs.Commons
import "Wallpaper.js" as Wallpaper
import "../displays/Model.js" as Model
import "." as WallpaperUi
import "../platform" as Platform

Item {
  id: root
  // Data and finite effects only: this owner never sees the Service object.
  property var monitors: []
  property var savedPreferences: ({})
  property bool configLoaded: false
  property string stateDir: ""
  property string pluginDir: ""
  property var enqueue: null
  property var publishPreferences: null
  property var savePreferences: null
  property var releasePanel: null
  property var returnPanel: null
  readonly property var layout: Wallpaper.topology(monitors, Model.identities(monitors))
  readonly property var preferences: Wallpaper.settings(savedPreferences)
  property string themePath: ""
  property string themeName: ""
  property string themeRevision: ""
  readonly property string themeStateDir: Quickshell.env("HOME") + "/.local/state/omarchy/current"
  property string themeWatchDirectory: ""
  property bool themeWatchRestarting: false
  property bool themeRereadPending: false
  readonly property bool themeWatching: themeWatch.running
  readonly property string themeKey: JSON.stringify([themeName, themePath])
  readonly property string themeToken: JSON.stringify([themeName, themePath, themeRevision])
  onConfigLoadedChanged: if (configLoaded) startThemeWatch()
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
  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string omarchyDir: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  // Omarchy themes listed on demand for the in-panel pickers, and a theme or Omarchy
  // background chosen there. Neither reaches Omarchy until Apply.
  property var themes: []
  property bool themesLoading: false
  property string pendingTheme: ""
  property string pendingBackground: ""
  // While Apply runs the Omarchy command: the theme it should leave current.
  property string themeSwitchName: ""
  property bool themeSwitchExited: false
  property bool themeReadAfterSwitch: false
  readonly property bool pickerBusy: picker.running || pickerDelay.running || importBusy
  onAppliedChanged: {
    if (!dirty && !busy && !importBusy) reset()
    Qt.callLater(prepareLegacyWallpaper)
  }
  onThemeTokenChanged: {
    // Station's own Omarchy command finishes once a read after its exit settles.
    if (themeSwitchName) return
    if (pendingTheme && pendingTheme === themeName) { pendingTheme = ""; pendingBackground = "" }
    else if (!pendingTheme && pendingBackground) pendingBackground = ""
    // A theme switch wins over an in-flight Apply only while following it.
    if (busy && pending && !pendingSave && pending.scene.followTheme) {
      serial++; busy = false; pending = null
      showNotice("Wallpaper changed with Omarchy. Review your selection and apply again.")
    }
    if (draft.followTheme && !pendingTheme) {
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
    var prefix = stateDir + "/wallpapers/"
    var paths = [next.source]
    Object.keys(next.perDisplay).forEach(function(key) { paths.push(next.perDisplay[key]) })
    next.safe = next.safe && paths.every(function(path) { return path.indexOf(prefix) === 0 })
    return next
  }
  function clearNotice() { notice = ""; noticeError = false }
  function reset() {
    draft = JSON.parse(JSON.stringify(applied)); dirty = false
    pendingTheme = ""; pendingBackground = ""
    clearNotice()
  }
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
      publishPreferences(repairPrevious)
      repairPrevious = null
      showNotice("Could not safely prepare the saved wallpaper. Choose it again.", true)
      return
    }
    if (!pendingSave) return
    pendingSave = false; pending = null; busy = false
    publishPreferences(previousPreferences)
    showNotice("Could not save preferences. Your previous wallpaper has been restored.", true)
  }
  function change(key, value) {
    if (busy || importBusy) return
    var next = JSON.parse(JSON.stringify(draft))
    next[key] = value
    if (key === "followTheme" && value === true)
      next = followScene(pendingTheme || themeName, pendingTheme ? pendingBackground : "")
    draft = next; dirty = true; clearNotice()
  }
  // The Follow scene a theme and background would give: their saved profile, keyed the
  // way Omarchy will report them, previewed from the background's own file.
  function followScene(name, value) {
    var settings = Object.assign({}, preferences, { mode: draft.mode, followTheme: true })
    var background = Wallpaper.themeBackground(Wallpaper.themeEntry(themes, name), value)
    if (!background || (name === themeName && background.omarchy === themePath))
      return Wallpaper.resolve(settings, themeKey, themePath, themeRevision)
    return Wallpaper.resolve(settings, JSON.stringify([name, background.omarchy]), background.path, "")
  }
  function loadThemes() {
    if (themesLoading || !pluginDir || !homeDir) return false
    themesLoading = true
    enqueue(["perl", pluginDir + "/lib/wallpaper/ListThemes.pl", homeDir + "/.config/omarchy/themes",
      omarchyDir + "/themes", homeDir + "/.config/omarchy/backgrounds",
      homeDir + "/.local/state/omarchy/theme-backgrounds", themeStateDir + "/theme"], function(code, output) {
      root.themesLoading = false
      if (code !== 0) { root.showNotice("Could not list Omarchy themes.", true); return }
      root.themes = Wallpaper.themeList(output)
    })
    return true
  }
  // A theme is global. Under Follow every monitor previews the background it will open on.
  function previewTheme(name) {
    if (busy || importBusy) return false
    var theme = Wallpaper.themeEntry(themes, Wallpaper.themeName(name))
    if (!theme) return false
    var current = theme.name === themeName
    pendingTheme = current ? "" : theme.name
    pendingBackground = current ? "" : theme["default"]
    if (draft.followTheme) draft = followScene(theme.name, pendingBackground)
    dirty = true
    if (draft.followTheme || current) clearNotice()
    else showNotice("Follow Omarchy theme is off, so your wallpaper stays as it is.")
    return true
  }
  // With a monitor identity the background becomes that monitor's own image. Without
  // one it becomes Omarchy's background, which every following monitor shows.
  function previewBackground(value, identity) {
    if (busy || importBusy || pickerBusy) return false
    var name = pendingTheme || themeName
    var background = Wallpaper.themeBackground(Wallpaper.themeEntry(themes, name), value)
    if (!background) return false
    if (identity) {
      if (draft.mode !== "individual" || !layout.displays.some(function(display) { return display.identity === identity })) return false
      prepareSelection(background.path, identity)
      return true
    }
    pendingBackground = !pendingTheme && background.omarchy === themePath ? "" : background.path
    draft = followScene(name, background.path)
    dirty = true; clearNotice()
    return true
  }
  function frame(value) { change("framing", Wallpaper.framing(value)) }
  function frameDisplay(identity, value) {
    if (draft.mode === "span" || !layout.displays.some(function(display) { return display.identity === identity })) return
    change("frames", Wallpaper.withFrame(draft, identity, value).frames)
  }
  function sanitizedPath(output) {
    var path = String(output || "").replace(/\n$/, "")
    var prefix = stateDir + "/wallpapers/"
    return Wallpaper.path(path) && path.indexOf(prefix) === 0 ? path : ""
  }
  function stagePath(path, generation, index, done) {
    if (!Wallpaper.path(path) || !pluginDir) { done(1, ""); return }
    var folder = stateDir + "/wallpapers/import-" + Date.now() + "-" + generation + "-" + index
    enqueue(["perl", pluginDir + "/lib/wallpaper/SanitizeWallpaper.pl", path, folder], function(code, output) {
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
    if (!sanitizedPath(path)) { showNotice("Choose a local image file.", true); return }
    change("followTheme", false)
    if (target) {
      var map = Object.assign({}, draft.perDisplay); map[target] = path
      change("perDisplay", map)
    } else { change("source", path); frame({}) }
    change("frames", Wallpaper.framesWithoutImage(draft, target))
    change("safe", true)
  }
  function prepareSelection(path, identity) {
    if (!Wallpaper.path(path)) { showNotice("Choose a local image file.", true); return }
    var target = identity === undefined ? pickerTarget : identity
    var generation = ++serial
    importBusy = true; showNotice("Preparing wallpaper safely…")
    // Keep other monitors on a private copy of the current theme image when a
    // per-monitor selection turns Follow off.
    var baseline = draft.followTheme && target ? draft.source : ""
    var paths = baseline && baseline !== path ? [path, baseline] : [path]
    stagePaths(paths, generation, function(code, prepared) {
      if (generation !== root.serial) return
      root.importBusy = false
      if (code !== 0) { root.showNotice("The image could not be prepared safely. Choose another file.", true); return }
      if (baseline) root.change("source", prepared[baseline])
      root.acceptSanitized(prepared[path], target)
    })
  }

  function prepareLegacyWallpaper() {
    if (!configLoaded || !pluginDir || dirty || busy || importBusy
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
      root.repairPrevious = root.savedPreferences
      root.repairLegacyKey = key
      root.repairPending = true
      root.publishPreferences(Wallpaper.settings(settings))
      root.savePreferences()
    })
  }
  function choose(identity) {
    if (typeof identity !== "string" || (identity !== "" && !layout.displays.some(function(display) { return display.identity === identity }))) return false
    if (pickerBusy || busy) return false
    pickerTarget = identity || ""
    // The picker is a separate native window: release the panel's focus grab.
    releasePanel()
    pickerDelay.restart()
    return true
  }
  function useTheme() {
    change("source", themePath); change("perDisplay", {}); change("safe", true); frame({}); change("frames", {})
  }
  function apply() {
    if (busy || importBusy || !dirty || !layout.displays.length) return
    if (pendingTheme || pendingBackground) { startThemeSwitch(); return }
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
  // Omarchy applies the theme or background first, with its own transition. The
  // wallpaper profile is saved only once a theme read after the command confirms it.
  function startThemeSwitch() {
    var name = pendingTheme || themeName
    var background = Wallpaper.themeBackground(Wallpaper.themeEntry(themes, name), pendingBackground)
    var command = pendingTheme
      ? Wallpaper.themeCommand(pendingTheme, background, homeDir + "/.local/state/omarchy/theme-backgrounds")
      : Wallpaper.backgroundCommand(background)
    if (!command || !homeDir) {
      pendingTheme = ""; pendingBackground = ""
      showNotice("That theme is no longer available. Choose it again.", true)
      return
    }
    serial++; busy = true
    showNotice(pendingTheme ? "Applying " + Wallpaper.themeEntry(themes, name).label + "…" : "Applying background…")
    themeSwitchName = name; themeSwitchExited = false
    themeSwitch.command = command
    themeSwitch.running = true
  }
  function themeSwitchEnded(code) {
    if (!themeSwitchName) return
    if (code !== 0) {
      themeSwitchName = ""; busy = false
      showNotice("Omarchy could not apply the theme. Your previous theme is unchanged.", true)
      return
    }
    themeSwitchExited = true
    themeSwitchTimeout.restart()
    readTheme()
  }
  function finishThemeSwitch(timedOut) {
    if (!themeSwitchName || !themeSwitchExited) return
    var target = themeSwitchName
    if (themeName !== target && !timedOut) return
    themeSwitchTimeout.stop()
    themeSwitchName = ""; themeSwitchExited = false; busy = false
    if (themeName !== target) {
      showNotice("Omarchy did not report the new theme. Review your selection and apply again.", true)
      return
    }
    pendingTheme = ""; pendingBackground = ""
    if (draft.followTheme) {
      var next = JSON.parse(JSON.stringify(draft))
      next.source = themePath; next.revision = themeRevision
      draft = next
    }
    apply()
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
    var job = pending, folder = stateDir + "/wallpapers/" + Date.now() + "-" + job.serial
    var destinations = job.paths.map(function(p, i) { return folder + "/" + i + "/" + p.split("/").pop() })
    // Fixed script; every path is a quoted positional argument. Originals and
    // Omarchy's current/background link are never changed. Snapshots survive
    // theme regeneration at the same pathname and deletion of a chosen file.
    var script = 'set -eu; umask 077; folder=$1; shift; mkdir -p -- "${folder%/*}"; mkdir -- "$folder"; while [ "$#" -gt 0 ]; do mkdir -- "${2%/*}"; cp --reflink=auto -- "$1" "$2"; shift 2; done'
    var args = ["bash", "-c", script, "station-wallpaper", folder]
    job.paths.forEach(function(p, i) { args.push(p, destinations[i]) })
    enqueue(args, function(code) {
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
      root.previousPreferences = root.savedPreferences
      root.pendingSave = true
      root.publishPreferences(Wallpaper.settings(settings))
      root.savePreferences()
    })
  }

  // Omarchy names its background and theme with files in one directory. Watching that
  // directory, and the image's own directory for a replacement in place, costs nothing
  // until something changes.
  function startThemeWatch() { if (configLoaded && !themeWatch.running) themeWatch.running = true }
  function restartThemeWatch() {
    themeWatchRetry.stop()
    if (!themeWatch.running) { startThemeWatch(); return }
    themeWatchRestarting = true
    themeWatch.running = false
  }
  function readTheme() {
    if (themeRead.running) { themeRereadPending = true; return }
    themeReadAfterSwitch = themeSwitchExited
    themeRead.running = true
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
      root.themeStateDir + "/background", root.themeStateDir + "/theme.name"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.themeName = lines.length > 1 ? lines[1] : ""
        root.themePath = Wallpaper.path(lines[0])
        root.themeRevision = lines.length > 2 ? lines[2] : ""
        var directory = root.themeRevision ? Wallpaper.directory(root.themePath) : ""
        if (directory !== root.themeWatchDirectory) {
          root.themeWatchDirectory = directory
          root.restartThemeWatch()
        }
        if (root.themeReadAfterSwitch) { root.themeReadAfterSwitch = false; root.finishThemeSwitch(false) }
      }
    }
    onExited: function(code) {
      if (!root.themeRereadPending) return
      root.themeRereadPending = false
      Qt.callLater(root.readTheme)
    }
  }
  Timer { id: themeWatchDebounce; interval: 100; onTriggered: root.restartThemeWatch() }
  Timer { id: themeWatchRetry; interval: 5000; onTriggered: root.startThemeWatch() }
  Process {
    id: themeWatch
    command: Wallpaper.watchCommand(root.themeStateDir, root.themeWatchDirectory)
    stdout: SplitParser {
      onRead: function(line) {
        if (Wallpaper.watchRelevant(line, root.themeStateDir, root.themePath)) themeWatchDebounce.restart()
      }
    }
    // Read only once the watches exist, so a change made during a restart is not lost.
    stderr: SplitParser { onRead: function(line) { if (line.indexOf("Watches established") !== -1) root.readTheme() } }
    onExited: function(code) {
      if (root.themeWatchRestarting) {
        root.themeWatchRestarting = false
        Qt.callLater(root.startThemeWatch)
        return
      }
      // Missing tool, watch limit or a killed process: keep following at a slow rate.
      root.readTheme()
      themeWatchRetry.restart()
    }
  }
  Process {
    id: picker
    command: ["omarchy", "file", "select", "--title", "Choose wallpaper", "--extensions", "png jpg jpeg webp bmp gif"]
    property string result: ""
    onStarted: result = ""
    stdout: StdioCollector { onStreamFinished: picker.result = text.replace(/\n$/, "") }
    onExited: function(code) {
      if (code === 0) root.prepareSelection(result)
      else if (code !== 1) root.showNotice("The desktop file picker could not open.", true)
      root.returnPanel()
    }
  }
  Process {
    id: themeSwitch
    onExited: function(code) { root.themeSwitchEnded(code) }
  }
  // Omarchy names the theme before it returns; a missing report still frees Apply.
  Timer { id: themeSwitchTimeout; interval: 5000; onTriggered: root.finishThemeSwitch(true) }
  Timer { id: pickerDelay; interval: 200; onTriggered: picker.running = true }

  Image {
    id: introImage
    source: root.configLoaded && root.applied.followTheme ? Util.fileUrl(root.themePath) + "?station=" + encodeURIComponent(root.themeRevision) : ""
    asynchronous: true
    visible: false
  }
  WallpaperUi.IntroPlayback {
    id: introPlayback
    enabled: root.configLoaded && root.applied.followTheme && (root.applied.mode !== "same"
      || root.layout.displays.some(function(display) { return Wallpaper.hasFrame(root.applied, display) }))
    scene: root.applied
    layout: root.layout
    themeToken: root.themeToken
    returnReady: {
      var count = 0
      for (var surface of wallpaperSurfaces.instances) {
        if (!surface.display || surface.stock) continue
        count++
        if (!surface.visible || surface.returnFrames < 2) return false
      }
      return count > 0
    }
    imageWidth: introImage.status === Image.Ready ? introImage.sourceSize.width : 0
    imageHeight: introImage.status === Image.Ready ? introImage.sourceSize.height : 0
  }
  Variants {
    id: wallpaperSurfaces
    model: Quickshell.screens
    PanelWindow {
      id: surface
      required property var modelData
      readonly property var display: root.layout.displays.find(function(d) { return d.name === modelData.name }) || null
      readonly property bool stock: root.applied.mode === "same" && root.applied.followTheme && root.applied.source === root.themePath
        && !Wallpaper.hasFrame(root.applied, display)
      property int returnFrames: 0
      onVisibleChanged: if (!visible) returnFrames = 0
      Connections {
        target: introPlayback
        function onReturningChanged() { surface.returnFrames = 0 }
      }
      FrameAnimation {
        running: introPlayback.returning && surface.visible && surface.returnFrames < 2
        onTriggered: surface.returnFrames++
      }
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "station-wallpaper"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      color: "transparent"
      visible: root.configLoaded && display !== null && !stock && wallpaper.status === Image.Ready && !remap.remapping
      Platform.ScreenMoveRemap { id: remap; window: surface }
      WallpaperUi.WallpaperImage {
        id: wallpaper
        // Keep the layer mapped: remapping invokes Hyprland's layer fade and
        // exposes the stock wallpaper beneath it during the return handoff.
        visible: !introPlayback.exposed
        anchors.fill: parent
        scene: root.applied
        layout: root.layout
        display: surface.display || ({ width: 1, height: 1, x: 0, y: 0, identity: "" })
      }
    }
  }
}
