import QtQuick
import "MonitorsLua.js" as MonitorsLua
import "Tabs.js" as Tabs

// Persistent panel intent and the output-evacuation barrier. Both outlive every
// widget instance, because a bar rebuild destroys the panel. Deliberately
// in-memory: a shell restart starts with the panel closed.
Item {
  id: root
  property var closed: null
  property var continueApply: null
  property var continueRevert: null
  property var timedOut: null

  // The widget writes its open state on the way out; destruction cannot, so a
  // rebuilt widget reads true and asks for the panel back.
  property bool panelWanted: false
  // Preserve the output that owned the panel through a layout or bar rebuild.
  property string panelScreenName: ""
  property double panelTransferUntil: 0
  // Disabling the output that owns an open KeyboardPanel must be a two-step
  // hand-off. Its layer surface owns a Hyprland focus grab; destroying that
  // surface as part of monitor removal can crash Hyprland before migration.
  // The owning widget closes first and acknowledges after the surface has
  // unmapped, then the service focuses the surviving output and applies the
  // monitor rule. Only after that succeeds may the target widget reopen.
  property int panelEvacuationSerial: 0
  property int panelEvacuationWaiting: 0
  property string panelEvacuationFrom: ""
  property string panelEvacuationTo: ""
  property string panelEvacuationPurpose: ""
  // A rebuilt widget would otherwise start back on Displays.
  property int rememberedTab: 0
  // A temporary output disappearance must not erase the inspector's selection.
  property string rememberedDisplayName: ""

  function validConnector(value) {
    try { MonitorsLua.connector(value); return true } catch (error) { return false }
  }

  function setPanelWanted(value) {
    if (typeof value !== "boolean") return
    panelWanted = value
    if (!value && closed) closed()
  }
  function setPanelScreenName(value) {
    if (typeof value === "string" && (value === "" || validConnector(value))) panelScreenName = value
  }
  function setPanelTransferUntil(value) {
    if (typeof value === "number" && isFinite(value) && value >= 0) panelTransferUntil = value
  }
  function setRememberedTab(value) {
    if (Tabs.validIndex(value)) rememberedTab = value
  }
  function setRememberedDisplayName(value) {
    if (typeof value === "string" && (value === "" || validConnector(value))) rememberedDisplayName = value
  }

  function clearPanelEvacuation() {
    panelEvacuationTimeout.stop()
    panelEvacuationWaiting = 0
    panelEvacuationFrom = ""
    panelEvacuationTo = ""
    panelEvacuationPurpose = ""
  }

  function requestPanelEvacuation(from, to, purpose) {
    panelEvacuationFrom = from
    panelEvacuationTo = to
    panelEvacuationPurpose = purpose
    panelTransferUntil = Date.now() + 3000
    panelEvacuationWaiting = panelEvacuationSerial + 1
    panelEvacuationTimeout.restart()
    // Assign last: panel instances react to this notification only after
    // all request fields contain the complete hand-off.
    panelEvacuationSerial = panelEvacuationWaiting
  }

  function acknowledgePanelEvacuation(serial, screenName) {
    if (Number(serial) !== panelEvacuationWaiting || String(screenName || "") !== panelEvacuationFrom) return
    var purpose = panelEvacuationPurpose
    panelEvacuationTimeout.stop()
    panelEvacuationWaiting = 0
    if (purpose === "revert") continueRevert()
    else continueApply()
  }

  Timer {
    id: panelEvacuationTimeout
    // A replacement-bar widget polls every 1000 ms once its panel starts
    // closing, then waits 180 ms for the layer surface to unmap. Keep enough
    // scheduling margin for that guarded acknowledgement; no monitor rule is
    // dispatched until it arrives, and expiry still aborts safely.
    interval: 2500
    onTriggered: if (root.panelEvacuationWaiting) root.timedOut(root.panelEvacuationPurpose, root.panelEvacuationFrom)
  }
}
