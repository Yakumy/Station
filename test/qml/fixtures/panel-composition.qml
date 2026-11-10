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
  property var api: ({
    snapshot: function() { return JSON.parse(JSON.stringify(root.state)) },
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
      sourceComponent: PanelUi.StationPanel { bar: host; bridgeCurrent: function() { return root.api } }
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
        station.selectedTab = 5
      } else if (step === 2 || step === 7) {
        if (!require(root.state.rememberedTab === 5, "tab setter")) return
        var content = find(station, "stationTabContent", [])
        if (!require(content && content.children.length >= 7, "all tabs")) return
        var keys = content.children[5]
        keys.beginBindingEdit(root.state.bindStatuses[0]); keys.editingKey = "K"; keys.applyBindingEdit()
        if (!require(root.calls.some(function(row) { return row[0] === "setBinding" && row[1][1] === "SUPER + K" }), "key action")) return
        station.close()
      } else if (step === 3 || step === 8) {
        if (!require(!station.opened && !root.state.panelWanted && root.state.rememberedTab === 0, "explicit dismissal")) return
        if (step === 3) { station.bridgeApi = root.api; station.bridgeSnapshot = root.api.snapshot(); root.trusted = false; station.syncBridge() }
        else { console.log("PANEL_COMPOSITION_PASS direct and bridge paths, seven populated tabs, intent and key action"); stop(); Qt.quit(); return }
      }
      step++
    }
  }
}
