import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "Probe/displays" as Displays
import "Probe/keybindings" as Keys
import "Probe/panel" as PanelUi

Item {
  id: root
  width: 900; height: 600
  property var service: null
  property var trace: []
  property var peers: []
  property var view: null
  property bool peerSurfacesFound: true
  property var controls: null
  property var editor: null
  property var screenA: ({name: "A"})
  property var screenB: ({name: "B"})
  property var anchor: ({screen: screenA, width: 1920, height: 26})
  property var host: ({position: "top", barSize: 26, activePopout: null,
    moduleWidgets: function() { return root.peers }})
  function record(name, args) { trace = trace.concat([[name, args]]) }
  // COMPOSITION_PORTS
  QtObject {
    id: persistent
    property bool panelWanted: false
    property string panelScreenName: "A"
    property int rememberedTab: 0
    property double panelTransferUntil: 0
    property int panelEvacuationSerial: 0
    property int panelEvacuationWaiting: 0
    property string panelEvacuationFrom: ""
    property var panelEvacuationReleases: []
    property var enabledOutputs: []
    function displayEnabled(name) { return enabledOutputs.indexOf(name) !== -1 }
    property bool previewBusy: false
    property var displayDraft: []
    property bool draftEditable: true
    property string state: "idle"
    property string layoutError: ""
    property int previewSeconds: 12
    property var bindStatuses: []
    property var config: ({windows: {split: 50}})
    property bool windowSettingsBusy: false
    property bool displayWidgetEnabled: true
    property bool workspaceWidgetEnabled: true
    function setPanelWanted(value) { panelWanted = value; root.record("wanted", [value]) }
    function setPanelScreenName(value) { panelScreenName = value; root.record("screen", [value]) }
    function setPanelTransferUntil(value) { panelTransferUntil = value; root.record("deadline", [value]) }
    function setRememberedTab(value) { rememberedTab = value; root.record("tab", [value]) }
    function acknowledgePanelEvacuation(serial, screen) { root.record("ack", [serial, screen]) }
    function setBinding(id, combo) { root.record("binding", [id, combo]); return "ok" }
    function applyDisplaySetting(name, key, value) { root.record("display", [name, key, value]); return "started" }
    function setWindowSetting(key, value) { root.record("window", [key, value]); return "ok" }
    function monitorBar(name) { return {height: 30} }
    function monitorBarMinimum(name) { return 1 }
    function monitorBarMaximumHeight(name) { return 108 }
    function monitorBarMaximumContent(name) { return 24 }
  }
  Component {
    id: sessionComponent
    PanelUi.PanelSession {
      service: panelIntent
      isAvailable: function() { return !!root.service }
      directService: persistent
      bar: root.host
      anchorWindow: root.anchor
      hideSurface: function() { root.record("hide", []); root.view.opened = false }
      showSurface: function() { root.record("show", []); root.view.opened = true }
      syncBridge: function() { root.record("poll", []) }
      refreshControls: function() { root.record("refresh", []) }
      resetScroll: function() { root.record("scroll", []) }
      setPeerSurfacesVisible: function(names, visible) { root.record("peers", [names, visible]); return root.peerSurfacesFound }
      primeFocus: function() { root.record("prime", []) }
    }
  }
  Component { id: controlComponent; Displays.DisplayControls {} }
  QtObject {
    id: commonTokens
    property int regionPadH: 12
    property int space1: 4
    property int space2: 8
    property int space3: 12
    property int controlHeight: 30
  }
  Component { id: keyComponent; Keys.KeybindingsTab { width: 900; tokens: commonTokens; service: keybindingsTabPort } }
  TestCase {
    name: "PanelSession"; when: windowShown
    function initTestCase() { failOnWarning(/.*/) }
    function init() {
      failOnWarning(/.*/)
      persistent.bindStatuses = []
      root.service = null
      persistent.panelWanted = false; persistent.panelScreenName = "A"
      persistent.rememberedTab = 0; persistent.panelTransferUntil = 0
      persistent.previewBusy = false; persistent.panelEvacuationWaiting = 0
      persistent.panelEvacuationSerial = 0; persistent.panelEvacuationFrom = ""
      persistent.panelEvacuationReleases = []; persistent.enabledOutputs = []; root.peerSurfacesFound = true
      root.peers = []; root.anchor = {screen: screenA, width: 1920, height: 26}
      root.host = {position: "top", barSize: 26, activePopout: null, moduleWidgets: function() { return root.peers }}
      Quickshell.screens = [screenA, screenB]
      root.view = sessionComponent.createObject(root)
      root.controls = controlComponent.createObject(root)
      root.editor = keyComponent.createObject(root)
      verify(root.view); verify(root.controls); verify(root.editor)
      root.service = persistent; root.view.serviceResolved()
      root.trace = []
    }
    function cleanup() {
      root.view.destroy(); root.controls.destroy(); root.editor.destroy(); wait(0)
      root.view = null; root.controls = null
    }
    function process(owner, command) {
      for (var i = 0; i < owner.children.length; i++)
        if (owner.children[i].command !== undefined && owner.children[i].command[0] === command) return owner.children[i]
      return null
    }
    function count(name) { return root.trace.filter(function(row) { return row[0] === name }).length }
    function test_lateServiceIntentAndClose() {
      root.service = null
      root.view.opened = true
      verify(root.view.intentPending)
      root.service = persistent; root.view.serviceResolved()
      verify(persistent.panelWanted); compare(persistent.panelScreenName, "A")
      root.view.selectedTab = 4; compare(persistent.rememberedTab, 4)
      persistent.panelTransferUntil = Date.now() + 3000
      root.view.close()
      verify(!persistent.panelWanted); compare(persistent.rememberedTab, 0)
      compare(persistent.panelTransferUntil, 0); compare(count("hide"), 1)
      wait(50); compare(count("show"), 0)
    }
    function test_rebuildRestoresTabAndOutput() {
      root.view.opened = true; root.view.selectedTab = 3
      root.view.destroy(); wait(0)
      root.view = sessionComponent.createObject(root)
      root.view.serviceResolved(); root.view.requestPanelBack()
      tryVerify(function() { return root.view.opened })
      compare(root.view.selectedTab, 3); compare(count("show"), 1)
      compare(root.view.currentScreenName(), "A")
    }
    function test_screenRetentionAndAxis() {
      root.view.opened = true
      compare(root.view.currentScreenName(), "A")
      root.anchor = {screen: null, width: 1920, height: 26}
      compare(root.view.currentScreenName(), "A")
      root.host = {position: "left", barSize: 26}
      compare(root.view.barFacade.position, "left")
      root.anchor = {screen: null, width: 26, height: 1080}
      compare(root.view.barFacade.position, "left")
      root.host = {position: "bottom", barSize: 48}
      compare(root.view.barFacade.position, "bottom")
      compare(root.view.barFacade.barSize, 48)
      root.anchor = {screen: screenB, width: 1920, height: 26}
      compare(root.view.barFacade.position, "bottom")
      compare(root.view.currentScreenName(), "A")
      // Pill inset and custom thickness must not strand the previous edge.
      for (var edge of ["right", "top", "left", "bottom", "top"]) {
        root.host = {position: edge, barSize: 48}
        root.anchor = {screen: screenA, width: 1920, height: 56}
        compare(root.view.barFacade.position, edge)
        compare(root.view.barFacade.barSize, 48)
      }
    }
    function test_survivorWaitsForPreviewAndOldCopy() {
      persistent.panelWanted = true; persistent.previewBusy = true
      verify(!root.view.tryRestorePanel())
      persistent.previewBusy = false; persistent.panelScreenName = "B"
      verify(!root.view.tryRestorePanel())
      root.anchor = {screen: screenB, width: 1920, height: 26}
      root.peers = [{opened: true, currentScreenName: function() { return "B" }}]
      persistent.panelTransferUntil = Date.now() + 3000
      verify(!root.view.tryRestorePanel())
      root.peers = [{opened: true, currentScreenName: function() { return "A" }}]
      verify(root.view.tryRestorePanel()); verify(root.view.opened)
    }
    function test_disconnectedOutputFallback() {
      persistent.panelWanted = true; persistent.panelScreenName = "B"
      verify(!root.view.tryRestorePanel())
      Quickshell.screens = [screenA]
      tryVerify(function() { return root.view.opened })
    }
    function test_evacuationSerialAndDelayedAck() {
      root.view.opened = true
      persistent.panelEvacuationWaiting = 7
      persistent.panelEvacuationFrom = "B"; persistent.panelEvacuationSerial = 7
      compare(count("hide"), 0)
      persistent.panelEvacuationFrom = "A"
      root.view.handlePanelEvacuation()
      compare(count("hide"), 1); verify(root.view.monitorTransferClosing)
      verify(persistent.panelWanted); verify(root.view.popoutSwitchClosing)
      compare(count("ack"), 0); wait(100); compare(count("ack"), 0)
      tryCompare(root.view, "monitorTransferClosing", false, 500)
      compare(count("ack"), 1)
      compare(root.trace[root.trace.length - 1][1], [7, "A"])
      root.view.handlePanelEvacuation(); compare(count("hide"), 1)
    }
    function keptOpenHandOff() {
      root.view.opened = true
      persistent.previewBusy = true
      persistent.panelEvacuationWaiting = 8; persistent.panelEvacuationFrom = "A"
      persistent.panelEvacuationReleases = ["B"]; persistent.panelEvacuationSerial = 8
    }
    function test_survivingPanelStaysOpenThroughHandOff() {
      keptOpenHandOff()
      compare(count("hide"), 0); verify(root.view.opened)
      compare(count("peers"), 1); verify(!root.view.monitorTransferClosing)
      compare(count("ack"), 0)
      tryVerify(function() { return count("ack") === 1 }, 500)
      compare(root.trace.filter(function(row) { return row[0] === "ack" })[0][1], [8, "A"])
      verify(root.view.opened)
      // The output left, so nothing is shown again, but focus comes back.
      persistent.previewBusy = false
      compare(count("prime"), 1)
      var peers = root.trace.filter(function(row) { return row[0] === "peers" })
      compare(peers[peers.length - 1][1], [[], true])
    }
    function test_outputThatStayedGetsItsDismissSurfaceBack() {
      keptOpenHandOff()
      persistent.enabledOutputs = ["A", "B"]
      persistent.previewBusy = false
      var peers = root.trace.filter(function(row) { return row[0] === "peers" })
      compare(peers[peers.length - 1][1], [["B"], true])
    }
    function test_unknownHostFallsBackToClosing() {
      root.peerSurfacesFound = false
      keptOpenHandOff()
      compare(count("hide"), 1); verify(root.view.monitorTransferClosing)
      tryVerify(function() { return count("ack") === 1 }, 500)
    }
    function test_bridgeProbeAndPeerSwitch() {
      root.view.opened = true
      root.view.probeEvacuation(0)
      tryVerify(function() { return count("poll") > 0 })
      persistent.panelEvacuationWaiting = 1; persistent.panelEvacuationFrom = "A"
      persistent.panelEvacuationSerial = 1
      tryVerify(function() { return count("ack") === 1 })
      var polls = count("poll"); wait(70); compare(count("poll"), polls)
      root.peers = [{opened: true}]
      root.view.settlePopoutSwitch(persistent, null, root.host, 0)
      verify(persistent.panelWanted)
      root.peers = []; root.host = {activePopout: {foreign: true}, moduleWidgets: function() { return [] }}
      root.view.settlePopoutSwitch(persistent, null, root.host, Date.now() + 3000)
      verify(!persistent.panelWanted); compare(persistent.rememberedTab, 0)
    }
    function test_brightnessReadRaceAndUnavailable() {
      root.controls.selectedDisplayName = "A"
      var read = process(root.controls, "omarchy-brightness-display")
      verify(read); verify(root.controls.brightnessLoading)
      root.controls.selectedDisplayName = "B"
      read.finish(0, "60\n")
      compare(read.command[2], "B"); verify(read.running)
      verify(!root.controls.brightnessAvailable)
      read.finish(0, "unavailable\n"); verify(!root.controls.brightnessAvailable)
      root.controls.refreshBrightness(); read.finish(0, "72\n")
      verify(root.controls.brightnessAvailable); compare(root.controls.brightness, 72)
    }
    function test_brightnessReleaseAndPendingTarget() {
      root.controls.selectedDisplayName = "A"
      process(root.controls, "omarchy-brightness-display").finish(0, "50")
      root.controls.queueBrightness(70)
      root.controls.selectedDisplayName = "B"
      wait(100); verify(!process(root.controls, "omarchy"))
      tryVerify(function() { return !!process(root.controls, "omarchy") })
      var write = process(root.controls, "omarchy")
      compare(write.command.slice(-2), ["A", "70%"])
      root.controls.setBrightness(80, "A")
      write.finish(0, "")
      compare(write.command.slice(-2), ["A", "80%"])
      compare(root.controls.brightness, 50)
    }
    function test_textQueueFailureAndObservation() {
      root.controls.setTextSizeIndex(3)
      verify(!process(root.controls, "omarchy-display-text-size"))
      root.controls.setTextSizeIndex(4)
      var write = process(root.controls, "omarchy-display-text-size")
      compare(write.command[1], "13")
      root.controls.setTextSizeIndex(6); root.controls.setTextSizeIndex(7)
      write.finish(0, ""); compare(write.command[1], "20")
      compare(root.controls.queuedTextSize, -1)
      Style.font = Object.assign({}, Style.font, {baseSize: 20}); Style.fontBaseSizeChanged()
      compare(root.controls.textSizePreviewIndex, -1)
      write.finish(1, ""); compare(root.controls.textSizePreviewIndex, -1)
      Style.font = Object.assign({}, Style.font, {baseSize: 12})
    }
    function test_teardownCancelsTimersAndDrafts() {
      root.controls.selectedDisplayName = "A"
      process(root.controls, "omarchy-brightness-display").finish(0, "50")
      root.controls.queueBrightness(70)
      root.view.opened = true
      root.view.closeForMonitorTransfer(9, "A")
      root.controls.destroy(); root.view.destroy(); wait(0)
      root.controls = controlComponent.createObject(root)
      root.view = sessionComponent.createObject(root)
      wait(230)
      compare(count("ack"), 0); compare(root.controls.pendingBrightnessRequest, null)
      compare(root.controls.textSizePreviewIndex, -1)
      verify(!process(root.controls, "omarchy"))
    }
    function test_keyDraftCaptureAndTeardown() {
      persistent.bindStatuses = [{id: "switch-1", combo: "SUPER + 1", status: "conflict", owners: ["Personal"]}]
      root.editor.beginBindingEdit(persistent.bindStatuses[0])
      root.editor.active = true
      compare(root.editor.editingKey, "1"); verify(root.editor.editingModifiers.SUPER)
      root.editor.toggleEditingModifier("CTRL"); root.editor.editingKey = "K"
      root.editor.applyBindingEdit()
      compare(root.editor.editingBindingId, "")
      compare(root.trace[root.trace.length - 1], ["binding", ["switch-1", "SUPER + CTRL + K"]])
      root.editor.beginBindingEdit(persistent.bindStatuses[0])
      var picker = findChild(root.editor, "captureKey")
      verify(picker !== null)
      // The actual picker lives inside its FocusScope, and closes capture when tab activation ends.
      var scope = picker.parent.parent
      scope.startCapture(); verify(scope.capturing)
      root.editor.active = false; verify(!scope.capturing)
      root.editor.destroy(); wait(0)
      var commits = count("binding")
      root.editor = keyComponent.createObject(root)
      compare(root.editor.editingBindingId, ""); compare(count("binding"), commits)
    }
    function test_compositionPortsKeepArgumentsResultsAndBindings() {
      compare(displaysTabPort.applyDisplaySetting("B", "scale", 2), "started")
      compare(windowsTabPort.setWindowSetting("split", 65), "ok")
      compare(keybindingsTabPort.setBinding("switch-1", "SUPER + K"), "ok")
      persistent.bindStatuses = [{id: "switch-1", status: "conflict", combo: "SUPER + 1", owners: ["Personal"]}]
      compare(keybindingsTabPort.bindStatuses[0].status, "conflict")
      persistent.displayDraft = [{name: "B"}]
      compare(displaysTabPort.displayDraft[0].name, "B")
      root.service = null
      compare(keybindingsTabPort.setBinding("switch-1", "K"), undefined)
      compare(displaysTabPort.displayDraft.length, 0)
    }
  }
}
