import QtQuick
import qs.Commons
import "../platform/Store.js" as Store
import "../displays/MonitorsLua.js" as MonitorsLua

// One persistent feature owner. Inputs are data and finite effect ports, never
// the Service QObject. Preferences remain a projection of the root config file.
Item {
  id: root
  property var preferences: ({})
  property var hostConfig: null
  property var displays: []
  property bool configLoaded: false
  property bool panelWanted: false
  property string focusedBarScreenName: ""
  property var persistPreferences: null
  property var publishHost: null
  property var retainPanel: null
  property var requestLayerSync: null

  property string lastGlobalBarPosition: ""
  property var observedHostBars: ({})
  property var pendingMonitorBars: ({})
  property var monitorBarMinimums: ({})
  property var monitorBarMaximumContents: ({})
  readonly property string hostBarsSignature: JSON.stringify(hostConfig
    ? ((hostConfig.bar || hostConfig).monitors || {}) : {})
  readonly property string globalBarPosition: {
    var value = hostConfig ? (hostConfig.bar || hostConfig).position : ""
    return ["top", "bottom", "left", "right"].indexOf(value) !== -1 ? value : ""
  }
  onHostBarsSignatureChanged: Qt.callLater(adoptHostBars)
  onGlobalBarPositionChanged: Qt.callLater(syncGlobalBarPosition)
  onFocusedBarScreenNameChanged: Qt.callLater(syncFocusedBarMenu)
  onPreferencesChanged: Qt.callLater(syncFocusedBarMenu)
  onConfigLoadedChanged: { Qt.callLater(syncFocusedBarMenu); Qt.callLater(adoptHostBars) }

  Timer {
    id: publishDelay
    interval: 250
    onTriggered: { root.flushPendingMonitorBars(); root.syncFocusedBarMenu() }
  }
  function panelClosed() { publishDelay.restart() }
  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }
  function validConnector(value) {
    try { MonitorsLua.connector(value); return true } catch (error) { return false }
  }

  function adoptHostBars() {
    if (!configLoaded || !hostConfig || !activeStationBar()) return
    var rows = parseJson(hostBarsSignature, {})
    var bars = Object.assign({}, preferences || {}), pending = Object.assign({}, pendingMonitorBars), changed = false
    Object.keys(Object.assign({}, observedHostBars, rows)).forEach(function(name) {
      if (!validConnector(name) || JSON.stringify(rows[name]) === JSON.stringify(observedHostBars[name])) return
      if (!Object.prototype.hasOwnProperty.call(rows, name)) {
        delete bars[name]; delete pending[name]; changed = true; return
      }
      var input = {}; input[name] = rows[name]
      var clean = Store.loadConfig({ bars: input }).bars[name]
      if (JSON.stringify(bars[name]) !== JSON.stringify(clean)) { bars[name] = clean; changed = true }
      delete pending[name]
    })
    observedHostBars = JSON.parse(JSON.stringify(rows))
    pendingMonitorBars = pending
    if (changed) { persistPreferences(bars) }
  }

  function monitorBar(name) {
    var shellBar = hostConfig ? (hostConfig.bar || hostConfig) : null
    var fallback = shellBar ? String(shellBar.position || "top") : "top"
    if (["top", "bottom", "left", "right"].indexOf(fallback) === -1) fallback = "top"
    var row = preferences && preferences[name]
    var width = row && isFinite(Number(row.width))
      ? Math.max(1, Math.min(100, Math.round(Number(row.width)))) : 100
    var height = row && isFinite(Number(row.height))
      ? Math.max(0, Math.min(1000, Math.round(Number(row.height)))) : 0
    var background = row && ["solid", "transparent", "blur"].indexOf(row.background) !== -1
      ? row.background : "solid"
    var style = row && ["default", "pill"].indexOf(row.style) !== -1 ? row.style : "default"
    var contentSize = row && isFinite(Number(row.contentSize))
      ? Math.max(0, Math.min(1000, Math.round(Number(row.contentSize)))) : 0
    return row && typeof row === "object"
      ? { enabled: row.enabled !== false,
          position: ["top", "bottom", "left", "right"].indexOf(row.position) !== -1 ? row.position : fallback,
          width: width, height: height, background: background, style: style, contentSize: contentSize }
      : { enabled: true, position: fallback, width: 100, height: 0, background: "solid", style: "default", contentSize: 0 }
  }

  function monitorBarMaximumHeight(name) {
    var display = displays.find(function(item) { return item.name === name })
    if (!display) return 1
    var shorterSide = Math.min(Number(display.width) || 0, Number(display.height) || 0)
    return Math.max(1, Math.floor(shorterSide * 0.05))
  }

  function monitorBarRenderedHeight(name) {
    var bar = monitorBar(name)
    var minimum = bar.position === "left" || bar.position === "right"
      ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
    var maximum = Math.max(minimum, monitorBarMaximumHeight(name))
    return Math.max(minimum, Math.min(maximum, bar.height > 0 ? bar.height : minimum))
  }

  function monitorBarMinimum(name) {
    var value = Number(monitorBarMinimums && monitorBarMinimums[name])
    return isFinite(value) ? Math.max(1, Math.min(100, Math.round(value))) : 1
  }

  function reportMonitorBarMinimum(name, value) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    var number = Number(value)
    if (!isFinite(number) || number < 1 || number > 100) return "invalid"
    number = Math.round(number)
    if (monitorBarMinimum(name) === number && monitorBarMinimums[name] !== undefined) return "ok"
    var next = Object.assign({}, monitorBarMinimums)
    next[name] = number
    monitorBarMinimums = next
    return "ok"
  }

  function monitorBarMaximumContent(name) {
    var minimum = Math.max(1, Math.ceil(Style.font.body))
    var fallback = Math.max(minimum,
      monitorBarRenderedHeight(name) - Math.ceil(Style.spacing.sm) * 2)
    var value = Number(monitorBarMaximumContents && monitorBarMaximumContents[name])
    return isFinite(value) ? Math.max(minimum, Math.min(fallback, Math.round(value))) : fallback
  }

  function reportMonitorBarMaximumContent(name, value) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    var number = Number(value)
    if (!isFinite(number) || number < 1 || number > 1000) return "invalid"
    number = Math.round(number)
    if (monitorBarMaximumContent(name) === number && monitorBarMaximumContents[name] !== undefined) return "ok"
    var next = Object.assign({}, monitorBarMaximumContents)
    next[name] = number
    monitorBarMaximumContents = next
    return "ok"
  }

  function reconcileActiveBarLayout() {
    var shellBar = hostConfig ? (hostConfig.bar || hostConfig) : null
    if (!shellBar || String(shellBar.id || "") !== "yakumy.station"
        || !shellBar.layout || typeof shellBar.layout !== "object"
        || typeof publishHost !== "function") return false
    var found = ["left", "center", "right"].some(function(section) {
      return Array.isArray(shellBar.layout[section]) && shellBar.layout[section].some(function(entry) {
        return entry && String(entry.id || "") === "yakumy.station"
      })
    })
    if (!found) return false
    publishHost(function(scoped) {
      if (!scoped.bar || typeof scoped.bar !== "object"
          || !scoped.bar.layout || typeof scoped.bar.layout !== "object") return
      ;["left", "center", "right"].forEach(function(section) {
        if (!Array.isArray(scoped.bar.layout[section])) return
        scoped.bar.layout[section] = scoped.bar.layout[section].filter(function(entry) {
          return !entry || String(entry.id || "") !== "yakumy.station"
        })
      })
    })
    return true
  }

  function publishMonitorBar(name, next) {
    var changes = ({})
    changes[name] = next
    return publishMonitorBars(changes)
  }

  function publishMonitorBars(changes, menuPosition) {
    if (typeof publishHost !== "function") return false
    return publishHost(function(scoped) {
      if (!scoped.bar || typeof scoped.bar !== "object") scoped.bar = {}
      scoped.bar.id = "yakumy.station"
      if (["top", "bottom", "left", "right"].indexOf(menuPosition) !== -1)
        scoped.bar.position = menuPosition
      if (!scoped.bar.monitors || typeof scoped.bar.monitors !== "object") scoped.bar.monitors = {}
      Object.keys(changes || {}).forEach(function(name) {
        var next = changes[name]
        scoped.bar.monitors[name] = {
          enabled: next.enabled, position: next.position, width: next.width, height: next.height,
          background: next.background, style: next.style, contentSize: next.contentSize
        }
      })
      if (scoped.bar.layout && typeof scoped.bar.layout === "object") {
        ;["left", "center", "right"].forEach(function(section) {
          if (!Array.isArray(scoped.bar.layout[section])) return
          scoped.bar.layout[section] = scoped.bar.layout[section].filter(function(entry) {
            return !entry || String(entry.id || "") !== "yakumy.station"
          })
        })
      }
    }) === true
  }

  function activeStationBar() {
    var shellBar = hostConfig ? (hostConfig.bar || hostConfig) : null
    return !!shellBar && String(shellBar.id || "") === "yakumy.station"
  }

  function deferMonitorBarPublish(name, next) {
    var pending = Object.assign({}, pendingMonitorBars)
    pending[name] = {
      enabled: next.enabled, position: next.position, width: next.width, height: next.height,
      background: next.background, style: next.style, contentSize: next.contentSize
    }
    pendingMonitorBars = pending
  }

  function flushPendingMonitorBars() {
    if (panelWanted || !Object.keys(pendingMonitorBars).length) return false
    var pending = pendingMonitorBars
    if (!publishMonitorBars(pending)) return false
    pendingMonitorBars = ({})
    return true
  }

  function syncFocusedBarMenu() {
    if (!configLoaded || panelWanted || !activeStationBar()) return
    // Do not overwrite an external menu request awaiting its deferred handler.
    if (!lastGlobalBarPosition || globalBarPosition !== lastGlobalBarPosition) return
    var name = focusedBarScreenName
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return
    var position = monitorBar(name).position
    if (position === globalBarPosition) return
    var bars = Object.assign({}, preferences || {})
    var changed = false
    displays.forEach(function(display) {
      if (!validConnector(display.name) || bars[display.name]) return
      bars[display.name] = monitorBar(display.name)
      changed = true
    })
    if (changed) {
      persistPreferences(bars)
    }
    // Keep the stock menu's current edge aligned with focus, without treating
    // our own mirror as a request to move another monitor.
    lastGlobalBarPosition = position
    if (!publishMonitorBars(bars, position)) lastGlobalBarPosition = globalBarPosition
  }

  function syncGlobalBarPosition() {
    var next = globalBarPosition
    if (!next) return
    var previous = lastGlobalBarPosition
    lastGlobalBarPosition = next
    // Initial attachment must preserve independently saved monitor positions.
    if (!previous) { syncFocusedBarMenu(); return }
    if (previous === next || !configLoaded || !activeStationBar()) return
    applyBarMenuPosition(focusedBarScreenName, next, previous)
  }

  function applyBarMenuPosition(name, position, previous) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    if (["top", "bottom", "left", "right"].indexOf(position) === -1) return "invalid"
    if (!configLoaded || !activeStationBar()) return "unavailable"
    lastGlobalBarPosition = position
    var names = Object.keys(preferences || {})
    displays.forEach(function(display) {
      if (names.indexOf(display.name) === -1) names.push(display.name)
    })
    var bars = Object.assign({}, preferences || {})
    names.forEach(function(connector) {
      if (!validConnector(connector)) return
      var next = monitorBar(connector)
      // Omarchy has already changed the fallback. Materialize inherited edges
      // from the previous value so an unconfigured peer does not move with it.
      if (!bars[connector]) next.position = previous
      if (connector === name) next.position = position
      bars[connector] = next
      // Replace any older deferred position so closing a panel cannot undo it.
      deferMonitorBarPublish(connector, next)
    })
    persistPreferences(bars)
    if (panelWanted) retainPanel("")
    if (typeof publishHost !== "function") return "unsupported"
    flushPendingMonitorBars()
    return "ok"
  }

  function setMonitorBarPosition(name, position) {
    if (!validConnector(name) || ["top", "bottom", "left", "right"].indexOf(position) === -1) return "invalid"
    if (!displays.some(function(display) { return display.name === name })) return "invalid"
    var next = monitorBar(name)
    next.position = position
    if (panelWanted) {
      retainPanel("bar")
    }
    var bars = Object.assign({}, preferences || {})
    bars[name] = next
    persistPreferences(bars)
    // Once Station's full bar is active, Bar.qml consumes the detached config
    // snapshot above. Do not feed the same click through shell.json while the
    // panel is open: the host can recreate the full bar and the panel with it.
    // Keep shell.json as a durable mirror, but update it after an ordinary
    // close. The first edit still publishes immediately because it must select
    // Station's full-bar entry and retire the old widget row atomically.
    if (activeStationBar() && panelWanted) {
      if (typeof publishHost !== "function") return "unsupported"
      deferMonitorBarPublish(name, next)
      return "ok"
    }
    return publishMonitorBar(name, next) ? "ok" : "unsupported"
  }

  function setMonitorBarEnabled(name, enabled) {
    if (!validConnector(name) || typeof enabled !== "boolean") return "invalid"
    var display = displays.find(function(item) { return item.name === name })
    if (!display) return "invalid"
    if (!enabled && display.enabled) {
      var survivor = displays.some(function(item) {
        return item.name !== name && item.enabled && monitorBar(item.name).enabled
      })
      if (!survivor) return "last-bar"
    }
    var next = monitorBar(name)
    next.enabled = enabled
    if (panelWanted) {
      retainPanel("bar")
    }
    var bars = Object.assign({}, preferences || {})
    bars[name] = next
    persistPreferences(bars)
    requestLayerSync()
    return publishMonitorBar(name, next) ? "ok" : "unsupported"
  }

  function setMonitorBarWidth(name, width) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    var number = Number(width)
    if (!isFinite(number) || number < 1 || number > 100) return "invalid"
    var next = monitorBar(name)
    next.width = Math.round(number)
    if (panelWanted) {
      retainPanel("bar")
    }
    var bars = Object.assign({}, preferences || {})
    bars[name] = next
    persistPreferences(bars)
    if (activeStationBar() && panelWanted) {
      if (typeof publishHost !== "function") return "unsupported"
      deferMonitorBarPublish(name, next)
      return "ok"
    }
    return publishMonitorBar(name, next) ? "ok" : "unsupported"
  }

  function setMonitorBarHeight(name, height) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    var number = Number(height)
    if (!isFinite(number) || number < 1 || number > monitorBarMaximumHeight(name)) return "invalid"
    var next = monitorBar(name)
    next.height = Math.round(number)
    if (panelWanted) {
      retainPanel("bar")
    }
    var bars = Object.assign({}, preferences || {})
    bars[name] = next
    persistPreferences(bars)
    if (activeStationBar() && panelWanted) {
      if (typeof publishHost !== "function") return "unsupported"
      deferMonitorBarPublish(name, next)
      return "ok"
    }
    return publishMonitorBar(name, next) ? "ok" : "unsupported"
  }

  function setMonitorBarBackground(name, background) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    if (["solid", "transparent", "blur"].indexOf(background) === -1) return "invalid"
    var next = monitorBar(name)
    next.background = background
    if (panelWanted) {
      retainPanel("bar")
    }
    var bars = Object.assign({}, preferences || {})
    bars[name] = next
    persistPreferences(bars)
    requestLayerSync()
    if (activeStationBar() && panelWanted) {
      if (typeof publishHost !== "function") return "unsupported"
      deferMonitorBarPublish(name, next)
      return "ok"
    }
    return publishMonitorBar(name, next) ? "ok" : "unsupported"
  }

  function setMonitorBarStyle(name, style) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    if (["default", "pill"].indexOf(style) === -1) return "invalid"
    var next = monitorBar(name)
    next.style = style
    if (panelWanted) {
      retainPanel("bar")
    }
    var bars = Object.assign({}, preferences || {})
    bars[name] = next
    persistPreferences(bars)
    if (activeStationBar() && panelWanted) {
      if (typeof publishHost !== "function") return "unsupported"
      deferMonitorBarPublish(name, next)
      return "ok"
    }
    return publishMonitorBar(name, next) ? "ok" : "unsupported"
  }

  function setMonitorBarContentSize(name, contentSize) {
    if (!validConnector(name) || !displays.some(function(display) { return display.name === name })) return "invalid"
    var number = Number(contentSize)
    var minimum = Math.max(1, Math.ceil(Style.font.body))
    if (!isFinite(number) || number < minimum || number > monitorBarMaximumContent(name)) return "invalid"
    var next = monitorBar(name)
    next.contentSize = Math.round(number)
    if (panelWanted) {
      retainPanel("bar")
    }
    var bars = Object.assign({}, preferences || {})
    bars[name] = next
    persistPreferences(bars)
    if (activeStationBar() && panelWanted) {
      if (typeof publishHost !== "function") return "unsupported"
      deferMonitorBarPublish(name, next)
      return "ok"
    }
    return publishMonitorBar(name, next) ? "ok" : "unsupported"
  }

}
