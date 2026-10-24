import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import "lib" as Station
import "lib/BarBridge.js" as BarBridge

// Station's full-bar entry. Each connected output owns an isolated copy of
// Omarchy's bar, so position and presence can differ without patching the
// system shell. The copies still consume the host's shared widget registry,
// layout, theme, and capability-scoped shell facade.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var barConfig: ({})
  property var shell: null
  property var manifest: null
  property var instances: []
  // The persistent service owns per-monitor policy. Read its detached snapshot
  // directly from this top-level entry point (the same .pragma-library context
  // as Panel.qml and Service.qml) so an open panel can move its bar without
  // making the host reload shell.json. The service mirrors the choice there
  // after the panel closes.
  property var stationBars: ({})
  property var stationBarMaximumHeights: ({})
  property string stationBarsKey: ""

  readonly property string focusedScreenName: Hyprland.focusedMonitor
    ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property string position: validPosition(monitorEntry(focusedScreenName).position || defaultPosition())
  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: preferredInstance()
    ? preferredInstance().barSize : (vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
  readonly property string fontFamily: Style.font.family
  readonly property bool barHidden: instances.length ? instances[0].barHidden === true : false

  function validPosition(value) {
    var text = String(value || "")
    return ["top", "bottom", "left", "right"].indexOf(text) !== -1 ? text : "top"
  }

  function defaultPosition() {
    return validPosition(barConfig && barConfig.position)
  }

  function monitorEntry(name) {
    var live = stationBars && typeof stationBars === "object"
      ? stationBars[String(name || "")] : null
    if (live && typeof live === "object") return live
    var rows = barConfig && barConfig.monitors
    var row = rows && typeof rows === "object" ? rows[String(name || "")] : null
    return row && typeof row === "object" ? row : ({})
  }

  function configuredEnabledCount() {
    var count = 0
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (monitorEntry(Quickshell.screens[i].name).enabled !== false) count++
    return count
  }

  function enabledFor(screen) {
    if (!screen) return false
    if (configuredEnabledCount() > 0) return monitorEntry(screen.name).enabled !== false
    // A malformed external edit must not make every recovery control vanish.
    return Quickshell.screens.length > 0 && screen === Quickshell.screens[0]
  }

  function configFor(screen) {
    var copy = JSON.parse(JSON.stringify(barConfig || {}))
    var entry = monitorEntry(screen ? screen.name : "")
    copy.position = validPosition(entry.position || copy.position)
    copy.widthPercent = Number(entry.width) > 0 ? Number(entry.width) : 100
    copy.height = Number(entry.height) > 0 ? Number(entry.height) : 0
    copy.background = ["solid", "transparent", "blur"].indexOf(entry.background) !== -1
      ? entry.background : (copy.transparent === true ? "transparent" : "solid")
    copy.transparent = copy.background === "transparent"
    copy.maximumHeight = Number(stationBarMaximumHeights[screen ? screen.name : ""]) || 0
    return copy
  }

  function reportMinimumWidth(instance) {
    if (!instance || !instance.targetScreenName) return
    var api = BarBridge.current()
    if (api && typeof api.call === "function")
      api.call("reportMonitorBarMinimum", [instance.targetScreenName, instance.minimumWidthPercent])
  }

  function refreshStationBars() {
    var api = BarBridge.current()
    var snapshot = api && typeof api.snapshot === "function" ? api.snapshot() : null
    var bars = snapshot && snapshot.config && snapshot.config.bars
    if (!bars || typeof bars !== "object") bars = ({})
    var maximumHeights = ({})
    var displays = snapshot && Array.isArray(snapshot.displayDraft) ? snapshot.displayDraft : []
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      maximumHeights[String(display.name || "")] = Math.max(1,
        Math.floor(Math.min(Number(display.width) || 0, Number(display.height) || 0) * 0.1))
    }
    var key = JSON.stringify({ bars: bars, maximumHeights: maximumHeights })
    if (key === stationBarsKey) return
    stationBarsKey = key
    stationBars = JSON.parse(JSON.stringify(bars))
    stationBarMaximumHeights = JSON.parse(JSON.stringify(maximumHeights))
  }

  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: root.refreshStationBars()
  }

  Component.onCompleted: refreshStationBars()

  function registerInstance(instance) {
    if (!instance || instances.indexOf(instance) !== -1) return
    instances = instances.concat([instance])
  }

  function unregisterInstance(instance) {
    instances = instances.filter(function(candidate) { return candidate && candidate !== instance })
  }

  function closePeerPopouts(source) {
    for (var i = 0; i < instances.length; i++)
      if (instances[i] && instances[i] !== source) instances[i].closeActivePopout()
  }

  function requestMonitorBackground(instance, background) {
    if (!instance || !instance.targetScreenName) return
    var api = BarBridge.current()
    var result = api && typeof api.call === "function"
      ? api.call("setMonitorBarBackground", [instance.targetScreenName, background]) : undefined
    if (result !== undefined) return
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!config.bar || typeof config.bar !== "object") config.bar = {}
        if (!config.bar.monitors || typeof config.bar.monitors !== "object") config.bar.monitors = {}
        var current = config.bar.monitors[instance.targetScreenName]
        if (!current || typeof current !== "object") current = {}
        current.background = background
        config.bar.monitors[instance.targetScreenName] = current
      })
    }
  }

  function moduleWidgets(pluginId) {
    var result = []
    for (var i = 0; i < instances.length; i++)
      result = result.concat(instances[i].moduleWidgets(pluginId))
    return result
  }

  function preferredInstance() {
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    for (var i = 0; i < instances.length; i++)
      if (instances[i].targetScreenName === focused) return instances[i]
    for (var j = 0; j < instances.length; j++)
      if (instances[j].targetScreen) return instances[j]
    return null
  }

  function summonBarWidget(pluginId) {
    var instance = preferredInstance()
    return instance ? instance.summonBarWidget(pluginId) : false
  }

  function hideBarWidget(pluginId) {
    var hidden = false
    for (var i = 0; i < instances.length; i++)
      hidden = instances[i].hideBarWidget(pluginId) || hidden
    return hidden
  }

  function isBarWidgetOpen(pluginId) {
    for (var i = 0; i < instances.length; i++)
      if (instances[i].isBarWidgetOpen(pluginId)) return true
    return false
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      Station.MonitorBar {
        id: monitorBar
        required property var modelData
        targetScreen: root.enabledFor(modelData) ? modelData : null
        omarchyPath: root.omarchyPath
        barWidgetRegistry: root.barWidgetRegistry
        pluginRegistry: root.pluginRegistry
        shell: root.shell
        manifest: root.manifest
        barConfig: root.configFor(modelData)
        onPopoutRequested: root.closePeerPopouts(monitorBar)
        onBackgroundModeRequested: function(mode) { root.requestMonitorBackground(monitorBar, mode) }
        onMinimumWidthPercentChanged: root.reportMinimumWidth(monitorBar)
        Component.onCompleted: {
          root.registerInstance(monitorBar)
          Qt.callLater(function() { root.reportMinimumWidth(monitorBar) })
        }
        Component.onDestruction: root.unregisterInstance(monitorBar)
      }
    }
  }
}
