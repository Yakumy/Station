import QtQuick
import Quickshell.Io
import "omarchy/BarModel.js" as BarModel

// Station may hide Omarchy's stock workspace and monitor widgets. A lease records
// whether Station did the hiding and where the widget sat, so startup and removal
// restore only what Station took. Plugin writes rebuild the bar: serialize them.
Item {
  id: root
  property var shell: null
  property bool started: false
  property var config: ({})
  property var persisted: ({})
  property var saveState: null
  property var enqueue: null

  property int stockDisableAttempts: 0
  property int displayDisableAttempts: 0
  property var displayWidgetEnabled: null
  property var workspaceWidgetEnabled: null
  property bool displayShowPending: false
  property bool workspaceShowPending: false
  readonly property bool stockDisableRunning: stockDisable.running
  readonly property bool displayDisableRunning: displayDisable.running

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }

  function barPlacement(widgetId) {
    var layout = shell && shell.barConfig && shell.barConfig.bar ? shell.barConfig.bar.layout : null
    if (!layout) return null
    var sections = BarModel.sections
    for (var s = 0; s < sections.length; s++) {
      var rows = layout[sections[s]] || []
      for (var i = 0; i < rows.length; i++) if (BarModel.entryId(rows[i]) === widgetId)
        return { section: sections[s], index: i }
    }
    return null
  }

  function acquireStockLeases() {
    if (!started || pluginList.running) return
    pluginList.running = true
  }

  function restoreStockLease(forceShow) {
    if (forceShow) workspaceShowPending = true
    if (stockDisable.running) return
    var lease = persisted.stockLease
    if (!lease && !forceShow) return
    if (forceShow || (lease && lease.disabledByStation && lease.wasEnabled)) {
      var place = lease || { section: "left", index: 1 }
      enqueue(["omarchy", "plugin", "enable", "omarchy.workspaces"], function(code) {
        if (code !== 0) { root.workspaceShowPending = false; leaseVerify.restart(); return }
        if (root.config.hideNative) {
          root.workspaceShowPending = false
          root.acquireStockLeases()
          return
        }
        // Re-enabling alone drops it in the centre, and the recorded spot is
        // where it sat before Station leased it: between the Omarchy menu mark
        // and our own widget. Park it behind Station instead so the row reads
        // menu, Station, workspaces; the recorded section/index only covers a
        // bar that has since dropped the Station widget.
        root.enqueue(["omarchy", "bar", "move", "omarchy.workspaces", "--after",
          "yakumy.station"], function(afterCode) {
          if (afterCode === 0) {
            root.persisted.stockLease = null
            root.workspaceShowPending = false
            root.saveState()
            return
          }
          root.enqueue(["omarchy", "bar", "move", "omarchy.workspaces", "--section", place.section,
            "--index", String(place.index)], function() {
            root.persisted.stockLease = null
            root.workspaceShowPending = false
            root.saveState()
          })
        })
      })
    } else {
      persisted.stockLease = null
      saveState()
    }
  }

  function restoreDisplayLease(forceShow) {
    if (forceShow) displayShowPending = true
    if (displayDisable.running) return
    var lease = persisted.displayLease
    if (!lease && !forceShow) return
    if (forceShow || (lease && lease.disabledByStation && lease.wasEnabled)) {
      var place = lease || { section: "right", index: 5 }
      enqueue(["omarchy", "plugin", "enable", "omarchy.monitor"], function(code) {
        if (code !== 0) { root.displayShowPending = false; leaseVerify.restart(); return }
        if (root.config.hideDisplay) {
          root.displayShowPending = false
          root.acquireStockLeases()
          return
        }
        root.enqueue(["omarchy", "bar", "move", "omarchy.monitor", "--section", place.section,
          "--index", String(place.index)], function(moveCode) {
          if (moveCode === 0 && lease) {
            root.persisted.displayLease = null
            root.saveState()
          }
          root.displayShowPending = false
          leaseVerify.restart()
        })
      })
    } else {
      persisted.displayLease = null
      saveState()
    }
  }

  // Explicit Hide/Show from Settings. A deliberate Show also enables a widget
  // that was hidden before Station acquired it; startup and removal do not.
  function workspaceVisibilityChanged(hidden) {
    if (hidden) {
      workspaceShowPending = false
      stockDisableAttempts = 0
      acquireStockLeases()
    } else {
      restoreStockLease(true)
    }
  }

  function displayVisibilityChanged(hidden) {
    if (hidden) {
      displayShowPending = false
      displayDisableAttempts = 0
      acquireStockLeases()
    } else {
      restoreDisplayLease(true)
    }
  }

  function handleStockPlugins(raw) {
    var list = parseJson(raw, [])
    var changed = false
    var displayEntry = list.find(function(item) { return item.id === "omarchy.monitor" })
    var workspaceEntry = list.find(function(item) { return item.id === "omarchy.workspaces" })
    if (displayEntry) displayWidgetEnabled = !!displayEntry.enabled
    if (workspaceEntry) workspaceWidgetEnabled = !!workspaceEntry.enabled
    if (config.hideNative) {
      var workspaceEnabled = !!(workspaceEntry && workspaceEntry.enabled)
      if (persisted.stockLease) {
        if (persisted.stockLease.disabledByStation && workspaceEnabled
            && stockDisableAttempts < 3 && !stockDisable.running && !displayDisable.running) {
          stockDisableAttempts += 1
          stockDisable.running = true
        }
      } else {
        var workspacePlace = barPlacement("omarchy.workspaces") || { section: "left", index: 1 }
        persisted.stockLease = { wasEnabled: workspaceEnabled, section: workspacePlace.section,
          index: workspacePlace.index, disabledByStation: workspaceEnabled }
        changed = true
        if (workspaceEnabled && !stockDisable.running && !displayDisable.running) {
          stockDisableAttempts += 1
          stockDisable.running = true
        }
      }
    }
    if (config.hideDisplay) {
      var displayEnabled = !!(displayEntry && displayEntry.enabled)
      if (persisted.displayLease) {
        if (!persisted.displayLease.disabledByStation && displayEnabled) {
          var renewedPlace = barPlacement("omarchy.monitor") || persisted.displayLease
          persisted.displayLease = { wasEnabled: true, section: renewedPlace.section,
            index: renewedPlace.index, disabledByStation: true }
          changed = true
        }
        if (persisted.displayLease.disabledByStation && displayEnabled
            && displayDisableAttempts < 3 && !displayDisable.running && !stockDisable.running) {
          displayDisableAttempts += 1
          displayDisable.running = true
        }
      } else {
        var displayPlace = barPlacement("omarchy.monitor") || { section: "right", index: 5 }
        persisted.displayLease = { wasEnabled: displayEnabled, section: displayPlace.section,
          index: displayPlace.index, disabledByStation: displayEnabled }
        changed = true
        if (displayEnabled && !displayDisable.running && !stockDisable.running) {
          displayDisableAttempts += 1
          displayDisable.running = true
        }
      }
    }
    if (changed) saveState()
  }

  Process {
    id: pluginList
    command: ["omarchy-shell", "shell", "listPlugins"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: pluginList.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: function(code) { if (code === 0) root.handleStockPlugins(captured) }
  }

  Process {
    id: stockDisable
    command: ["omarchy", "plugin", "disable", "omarchy.workspaces"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.workspaceShowPending && !root.config.hideNative) root.restoreStockLease(true)
      leaseVerify.restart()
    }
  }

  Process {
    id: displayDisable
    command: ["omarchy", "plugin", "disable", "omarchy.monitor"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.displayShowPending && !root.config.hideDisplay) root.restoreDisplayLease(true)
      leaseVerify.restart()
    }
  }

  Timer { id: leaseVerify; interval: 600; onTriggered: if (!pluginList.running) pluginList.running = true }
}
