import QtQuick
import Quickshell
import qs.Commons
import "Station/panel" as PanelUi
import "Station/platform/Store.js" as Store
import "Station/wallpaper/Wallpaper.js" as Wallpaper
ShellRoot {
  id: root
  property var state: ({})
  property var calls: []
  readonly property var station: panelLoader.item
  property bool trusted: true
  property int snapshotReads: 0
  property int readsBeforeSwitch: 0
  property int readsAtIndicator: 0
  property double indicatorRequestedAt: 0
  property real indicatorLatency: -1
  property var api: ({
    snapshot: function() { root.snapshotReads++; return JSON.parse(JSON.stringify(root.state)) },
    station: function() { return root.state.currentStation },
    call: function(name, args) {
      root.calls.push([name, args])
      if (name === "monitorBar") return {enabled: true, position: "top", width: 100, height: 26, contentSize: 12, style: "default", background: "solid"}
      if (name === "monitorBarMinimum") return 1
      if (name === "monitorBarMaximumHeight") return 108
      if (name === "monitorBarMaximumContent") return 24
      if (name === "displayEnabled") return true
      if (name === "roleOf") return 0
      var field = {setPanelWanted:"panelWanted", setPanelScreenName:"panelScreenName", setPanelTransferUntil:"panelTransferUntil", setRememberedTab:"rememberedTab", setRememberedDisplayName:"rememberedDisplayName"}[name]
      if (field) { var next = Object.assign({}, root.state); next[field] = args[0]; root.state = next }
      return "ok"
    }
  })
  QtObject {
    id: host
    property QtObject shell: QtObject {
      function serviceFor(name) { return root.trusted ? observed : null }
    }
    property string position: "top"
    property int barSize: 26
    property color foreground: "white"
    property color barForeground: "white"
    property color background: "black"
    property color urgent: "red"
    property string fontFamily: Style.font.family
    property bool vertical: false
    property bool foregroundAnimationEnabled: false
    function hideTooltip(owner) {}
    function showTooltip(owner, text) {}
    property var activePopout: null
    property var clickTargets: []
    function moduleWidgets(name) { return [] }
    function requestPopout(owner) {}
    function releasePopout(owner) {}
    function targetBelongsToWindow(target, window) { return false }
  }
  PanelUi.BarServiceProxy { id: observed; snapshot: root.state.config ? root.state : null; api: root.api }
  Component.onCompleted: {
    var config = Store.loadConfig({})
    var screen = Quickshell.screens[0]
    root.state = {config: config, currentStation: 1, state:"idle", displayDraft: [{name:screen.name, identity:"test", enabled:true, width:1920, height:1080, x:0, y:0, scale:1, transform:0, lane:1, availableModes:["1920x1080@60.00Hz"], mode:"1920x1080@60.00Hz"}],
      bindStatuses:[{id:"switch-1", combo:"SUPER + 1", status:"conflict", owners:["Personal"]}],
      draftMode:"extend", draftSingleTarget:"", draftEditable:true, panelWanted:false, panelScreenName:screen.name,
      panelTransferUntil:0, panelEvacuationWaiting:0, panelEvacuationSerial:0, panelEvacuationFrom:"",
      rememberedTab:0, rememberedDisplayName:screen.name, pluginVersion:"test", previewBusy:false,
      previewSeconds:12, layoutError:"", windowSettingsBusy:false, monitorBarMinimums:{}, monitorBarMaximumContents:{},
      openApps:{}, workspaceApps:{}, workspaceMap:{outputs:[screen.name]}, workspaceTarget:{outputs:[screen.name]},
      workspaceWidgetEnabled:true, displayWidgetEnabled:true,
      wallpaper:{notice:"", themePath:"", draft:Wallpaper.resolve({},"",""), layout:{displays:[], width:1920, height:1080}}}
  }
  FloatingWindow {
    implicitWidth: 200; implicitHeight: 80; visible: true
    Loader {
      id: panelLoader
      active: root.state.config !== undefined
      sourceComponent: PanelUi.StationPanel {
        bar: host
        bridgeCurrent: function() { return root.api }
        onStationNumberChanged: if (root.indicatorRequestedAt > 0) {
          root.indicatorLatency = Date.now() - root.indicatorRequestedAt
          root.readsAtIndicator = root.snapshotReads
        }
      }
    }
  }
  function find(node, name, visited) {
    if (!node || visited.indexOf(node) >= 0) return null
    visited.push(node)
    if (node.objectName === name) return node
    var lists = [node.data || [], node.children || [], node.contentItem ? [node.contentItem] : []]
    for (var j = 0; j < lists.length; j++) for (var i = 0; i < lists[j].length; i++) {
      var found = find(lists[j][i], name, visited)
      if (found) return found
    }
    return null
  }
  function sliderClearance(node, visited) {
    if (!node || visited.indexOf(node) >= 0) return true
    visited.push(node)
    if (node.knobSize !== undefined && node.trackX !== undefined) {
      // The host enlarges the knob by 15% on hover. Check both endpoint
      // extents against the actual row, without issuing a slider release.
      var reach = node.knobSize * 1.15 / 2
      for (var end of [0, 1]) {
        var center = node.x + node.trackX(end)
        if (center - reach <= 0 || center + reach >= node.parent.width) return false
      }
    }
    var children = node.children || []
    for (var i = 0; i < children.length; i++)
      if (!sliderClearance(children[i], visited)) return false
    return true
  }
  Timer {
    interval: 180; running: true; repeat: true
    property int step: 0
    function require(value, message) {
      if (!value) { console.log("PANEL_COMPOSITION_FAIL " + message); stop(); Qt.quit() }
      return !!value
    }
    onTriggered: {
      if (step === 0 || step === 5) {
        if (!require(!!station.service && !!station.directService === root.trusted, "service selection")) return
        station.open()
      } else if (step === 1 || step === 6) {
        if (!require(station.opened && root.state.panelWanted, "open intent")) return
        station.selectedTab = 6
      } else if (step === 2 || step === 7) {
        if (!require(root.state.rememberedTab === 6, "tab setter")) return
        var content = find(station, "stationTabContent", [])
        if (!require(content && content.children.length >= 8, "all tabs")) return
        if (!require(root.sliderClearance(content, []), "hovered slider endpoint clearance")) return
        var keys = content.children[6]
        keys.beginBindingEdit(root.state.bindStatuses[0]); keys.editingKey = "K"; keys.applyBindingEdit()
        if (!require(root.calls.some(function(row) { return row[0] === "setBinding" && row[1][1] === "SUPER + K" }), "key action")) return
        station.close()
      } else if (step === 3 || step === 8) {
        if (!require(!station.opened && !root.state.panelWanted && root.state.rememberedTab === 0, "explicit dismissal")) return
        if (step === 3) { station.bridgeApi = root.api; station.bridgeSnapshot = root.api.snapshot(); root.trusted = false; station.syncBridge() }
        else {
          // Compact On keeps full snapshots one second apart, but its station
          // label is always visible. Confirm that the scalar timer wins.
          root.state = Object.assign({}, root.state, {config: Object.assign({}, root.state.config, {compactMode:"on"})})
          station.syncBridge()
        }
      } else if (step === 9) {
        root.readsBeforeSwitch = root.snapshotReads
        root.indicatorRequestedAt = Date.now()
        root.state = Object.assign({}, root.state, {currentStation: 2})
      } else if (step === 10) {
        if (!require(station.stationNumber === 2 && root.indicatorLatency >= 0 && root.indicatorLatency < 180,
            "indicator latency " + root.indicatorLatency)) return
        if (!require(root.readsAtIndicator === root.readsBeforeSwitch, "indicator copied a full snapshot")) return
        console.log("INDICATOR_LATENCY_MS " + root.indicatorLatency)
        console.log("PANEL_COMPOSITION_PASS direct and bridge paths, eight populated tabs, intent, key action and fast confirmed indicator")
      } else if (step >= 11 && step <= 22) {
        var index = Math.floor((step - 11) / 2)
        var content = find(station, "stationTabContent", [])
        var tab = content.children[index]
        if (step % 2 === 1) {
          station.selectedTab = index
          tab.narrow = true
        } else {
          var layout = find(tab, index === 1 ? "workspacesLayout" : index === 3 ? "windowsLayout" : "featureLayoutFrame", [])
          var controls = find(tab, "featureControlFrame", [])
          var divider = find(tab, "featureDivider", [])
          if (!require(layout && controls && divider, "geometry objects " + index)) return
          var bottom = layout.mapToItem(tab, 0, layout.height).y
          var top = controls.mapToItem(tab, 0, 0).y
          var line = divider.mapToItem(tab, 0, divider.height / 2).y
          if (!require(Math.abs((line - bottom) - (top - line)) < 1,
              "divider midpoint " + index + ": " + bottom + "/" + line + "/" + top)) return
          var controlBottom = controls.mapToItem(controls.parent.parent, 0, controls.height).y
          if (!require(Math.abs(controls.parent.parent.height - controlBottom - (line - bottom)) < 1,
              "matching bottom padding " + index)) return
          if (!require(Math.abs(layout.height - controls.height) < 1
              && Math.abs(layout.width - controls.width) < 1, "equal frames " + index)) return
        }
      } else if (step === 23) {
        console.log("PANEL_GEOMETRY_PASS six tall tabs with equal frames and centered dividers")
        station.open()
        var tab = find(station, "stationTabContent", []).children[1]
        station.selectedTab = 1
        tab.draft = Object.assign({}, tab.draft, {showOpenApps: !tab.draft.showOpenApps})
        tab.notice = ""
      } else if (step === 24) {
        var tab = find(station, "stationTabContent", []).children[1]
        var actions = find(tab, "workspacesActions", [])
        if (!require(tab.dirty && Math.abs(actions.y + actions.height / 2 - actions.parent.height / 2) < 1,
            "empty drawer centers buttons")) return
        tab.notice = "A longer workspace message that wraps above the action buttons."
      } else if (step === 25) {
        var tab = find(station, "stationTabContent", []).children[1]
        var actions = find(tab, "workspacesActions", [])
        var notice = find(tab, "workspacesNotice", [])
        if (!require(notice.visible && notice.y + notice.height <= actions.y, "drawer message stays above buttons")) return
        console.log("PANEL_DRAWER_PASS empty and populated compact drawers")
        stop(); Qt.quit(); return
      }
      step++
    }
  }
}
