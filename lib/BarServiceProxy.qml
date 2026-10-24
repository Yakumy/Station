import QtQuick
import "." as Station

QtObject {
  id: root
  property var snapshot: null
  property var api: null

  readonly property var config: snapshot ? snapshot.config : ({})
  readonly property var monitorBarMinimums: snapshot ? snapshot.monitorBarMinimums : ({})
  readonly property var displayDraft: snapshot ? snapshot.displayDraft : []
  readonly property var bindStatuses: snapshot ? snapshot.bindStatuses : []
  readonly property int currentStation: snapshot ? snapshot.currentStation : 1
  readonly property string draftMode: snapshot ? snapshot.draftMode : "extend"
  readonly property string draftSingleTarget: snapshot ? snapshot.draftSingleTarget : ""
  readonly property bool draftEditable: snapshot ? snapshot.draftEditable === true : false
  readonly property string state: snapshot ? snapshot.state : "idle"
  readonly property string layoutError: snapshot ? snapshot.layoutError : ""
  readonly property bool previewBusy: snapshot ? snapshot.previewBusy === true : false
  readonly property int previewSeconds: snapshot ? snapshot.previewSeconds : 0
  readonly property int panelEvacuationWaiting: snapshot ? Number(snapshot.panelEvacuationWaiting) : 0
  readonly property int panelEvacuationSerial: snapshot ? snapshot.panelEvacuationSerial : 0
  readonly property string panelEvacuationFrom: snapshot ? snapshot.panelEvacuationFrom : ""
  readonly property string panelScreenName: snapshot ? snapshot.panelScreenName : ""
  readonly property double panelTransferUntil: snapshot ? snapshot.panelTransferUntil : 0
  readonly property bool panelWanted: snapshot ? snapshot.panelWanted === true : false
  readonly property int rememberedTab: snapshot ? snapshot.rememberedTab : 0
  readonly property string rememberedDisplayName: snapshot ? snapshot.rememberedDisplayName : ""
  readonly property var displayWidgetEnabled: snapshot ? snapshot.displayWidgetEnabled : null
  readonly property var workspaceWidgetEnabled: snapshot ? snapshot.workspaceWidgetEnabled : null
  readonly property var manifest: ({ version: snapshot ? snapshot.pluginVersion : "" })

  readonly property var wallpaper: Station.WallpaperProxy {
    snapshot: root.snapshot ? root.snapshot.wallpaper : null
    api: root.api
  }

  function call(name, args) { return api ? api.call(name, args) : undefined }

  function setSetting(name, value) { return call("setSetting", [name, value]) }
  function setModeValue(mode, target) { return call("setModeValue", [mode, target]) }
  function setDirectionValue(value) { return call("setDirectionValue", [value]) }
  function setBinding(id, combo) { return call("setBinding", [id, combo]) }
  function approveBinding(combo) { return call("approveBinding", [combo]) }
  function setDisplayValue(name, key, value) { return call("setDisplayValue", [name, key, value]) }
  function setDisplayTransform(name, value) { return call("setDisplayTransform", [name, value]) }
  function setDisplayPosition(name, x, y) { return call("setDisplayPosition", [name, x, y]) }
  function setDisplayEnabled(name, enabled) { return call("setDisplayEnabled", [name, enabled]) }
  function setMonitorBarEnabled(name, enabled) { return call("setMonitorBarEnabled", [name, enabled]) }
  function setMonitorBarPosition(name, position) { return call("setMonitorBarPosition", [name, position]) }
  function setMonitorBarWidth(name, width) { return call("setMonitorBarWidth", [name, width]) }
  function reportMonitorBarMinimum(name, value) { return call("reportMonitorBarMinimum", [name, value]) }
  function monitorBar(name) {
    var revision = snapshot
    var value = call("monitorBar", [name])
    return value && typeof value === "object" ? value : ({ enabled: true, position: "top", width: 100 })
  }
  function monitorBarMinimum(name) {
    var revision = snapshot
    var value = call("monitorBarMinimum", [name])
    return value === undefined ? 1 : Number(value)
  }
  function applyDisplaySetting(name, key, value) { return call("applyDisplaySetting", [name, key, value]) }
  function swapRole(name, roleIndex) { return call("swapRole", [name, roleIndex]) }
  function previewLayout() { return call("previewLayout", []) }
  function keepPreview() { return call("keepPreview", []) }
  function revertPreview(reason) { return call("revertPreview", [reason || ""]) }
  function acquireStockLeases() { return call("acquireStockLeases", []) }
  function acknowledgePanelEvacuation(serial, screenName) {
    return call("acknowledgePanelEvacuation", [serial, screenName])
  }
  function setPanelWanted(value) { return call("setPanelWanted", [value]) }
  function setPanelScreenName(value) { return call("setPanelScreenName", [value]) }
  function setPanelTransferUntil(value) { return call("setPanelTransferUntil", [value]) }
  function setRememberedTab(value) { return call("setRememberedTab", [value]) }
  function setRememberedDisplayName(value) { return call("setRememberedDisplayName", [value]) }

  // These are queried from bindings. Read `snapshot` first so the binding
  // re-evaluates when the snapshot changes.
  function displayEnabled(name) {
    var revision = snapshot
    return call("displayEnabled", [name]) === true
  }
  function roleOf(name) {
    var revision = snapshot
    var value = call("roleOf", [name])
    return value === undefined ? -1 : Number(value)
  }
}
