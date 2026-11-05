import QtQuick
import Quickshell
import qs.Commons
import "Tabs.js" as Tabs
import "PanelPosition.js" as PanelPosition

// Visual session only. Persistent intent remains on Service.
Item {
  id: root
  // Only panel intent/evacuation state and setters cross this port.
  required property var service
  required property var isAvailable
  property var directService: null
  property var bridgeApi: null
  property var bar: null
  property var anchorWindow: null
  property bool opened: false
  property int selectedTab: 0
  property bool sessionTabRestored: false
  // Keep the actual screen during transient null anchor geometry on an axis change.
  property var retainedPanelScreen: null
  // Accept a new edge only when the bar window has finished changing its axis.
  property string stablePanelBarPosition: "top"
  property bool monitorTransferClosing: false
  property int monitorTransferSerial: 0
  property string monitorTransferScreen: ""
  property int handledEvacuationSerial: 0
  property bool popoutSwitchClosing: false
  required property var hideSurface
  required property var showSurface
  required property var syncBridge
  required property var refreshControls
  required property var resetScroll

  Timer {
    id: evacuationProbe
    interval: 30
    property int attempts: 0
    property int startingSerial: 0
    onTriggered: {
      // setModeValue starts the service transaction synchronously, but a
      // replacement bar only learns about its later evacuation request from
      // a bridge snapshot. Probe that operation directly so the panel can
      // unmap before the safety timeout even when the ordinary poll stalls.
      root.syncBridge()
      root.handlePanelEvacuation()
      if (root.isAvailable()
          && Number(root.service.panelEvacuationSerial) > startingSerial
          && root.handledEvacuationSerial >= Number(root.service.panelEvacuationSerial)) {
        attempts = 0
        return
      }
      if (attempts < 100) { attempts += 1; restart() } else attempts = 0
    }
  }

  // The service binding can still be empty when the panel changes state (the
  // bar configures this widget after it is created), so a transition that
  // happens before it resolves is replayed the moment it does. An open
  // recorded nowhere would leave a rebuilt widget thinking the panel was
  // closed; a close recorded nowhere would reopen a dismissed panel.
  property bool intentPending: false

  function currentScreenName() {
    var screen = currentPanelScreen()
    return screen ? String(screen.name || "") : ""
  }

  function screenByName(name) {
    var wanted = String(name || "")
    if (!wanted) return null
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (String(Quickshell.screens[i].name || "") === wanted) return Quickshell.screens[i]
    return null
  }

  function currentPanelScreen() {
    if (retainedPanelScreen) return retainedPanelScreen
    var window = anchorWindow
    if (window && window.screen) return window.screen
    return isAvailable() ? screenByName(service.panelScreenName) : null
  }

  function retainCurrentPanelScreen() {
    var window = anchorWindow
    var screen = window && window.screen ? window.screen : null
    if (!screen && isAvailable()) screen = screenByName(service.panelScreenName)
    if (screen) retainedPanelScreen = screen
  }

  // An explicit dismissal wins even if a bar rebuild is in progress.
  function close() {
    if (isAvailable()) {
      service.setPanelTransferUntil(0)
      // The proxy may still show the old transfer deadline until its next poll.
      // Record explicit dismissal now instead of relying on onOpenedChanged.
      service.setPanelWanted(false)
      service.setRememberedTab(0)
    }
    hideSurface()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    hideSurface()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function closeForMonitorTransfer(serial, screenName) {
    monitorTransferClosing = true
    monitorTransferSerial = serial
    monitorTransferScreen = screenName
    // Skip the 140 ms fade so the focus grab and layer surface are gone well
    // before Hyprland receives the monitor-disable rule.
    popoutSwitchClosing = true
    hideSurface()
    monitorTransferAck.restart()
  }

  function handlePanelEvacuation() {
    if (!isAvailable() || !service.panelEvacuationWaiting) return
    var serial = Number(service.panelEvacuationSerial)
    if (!serial || serial <= handledEvacuationSerial) return
    var mine = currentScreenName()
    if (!mine || mine !== service.panelEvacuationFrom) return
    handledEvacuationSerial = serial
    closeForMonitorTransfer(serial, mine)
  }

  function flushIntent() {
    if (!isAvailable() || !intentPending) return
    intentPending = false
    service.setPanelWanted(opened)
    if (opened && currentScreenName()) service.setPanelScreenName(currentScreenName())
    if (!opened) service.setRememberedTab(0)
  }

  // A popout switch is not a dismissal. The bar hands the popout to the
  // newer copy of this widget it just built, and closes us through
  // closeForPopoutSwitch while our destruction is still deferred — so the
  // panel is up on that copy a moment after we are told we closed. The
  // switch has not published its new owner yet from inside the close, so
  // decide afterwards whether any copy is still showing. Takes what it
  // reads as arguments: this instance may be gone by the time it runs.
  function settlePopoutSwitch(svc, api, barRef, transferUntil) {
    if ((!svc && !api) || !barRef) return
    var widgets = typeof barRef.moduleWidgets === "function"
      ? barRef.moduleWidgets("yakumy.station") : []
    var up = false
    for (var i = 0; i < widgets.length; i++) {
      if (widgets[i] && widgets[i].opened === true) { up = true; break }
    }
    function setWanted(value) {
      if (api) api.call("setPanelWanted", [value])
      else if (svc) svc.setPanelWanted(value)
    }
    function setTab(value) {
      if (api) api.call("setRememberedTab", [value])
      else if (svc) svc.setRememberedTab(value)
    }
    if (up) {
      setWanted(true)
    } else if ((barRef.activePopout && barRef.activePopout.foreign === true)
        || Date.now() >= transferUntil) {
      setWanted(false)
      setTab(0)
    }
  }

  onOpenedChanged: {
    if (opened) {
      retainCurrentPanelScreen()
      refreshControls()
      intentPending = true
      flushIntent()
    } else if (monitorTransferClosing) {
      // The explicit acknowledgment timer owns this close. Do not publish a
      // dismissal or let another widget reopen until the monitor rule lands.
    } else if (popoutSwitchClosing) {
      // Capture the persistent API, never the widget-owned proxy QObject.
      var svc = directService, api = directService ? null : bridgeApi
      var barRef = bar, settle = settlePopoutSwitch
      var transferUntil = service ? Number(service.panelTransferUntil) : 0
      if (svc || api) Qt.callLater(function() { settle(svc, api, barRef, transferUntil) })
    } else if (!isAvailable() || Date.now() >= service.panelTransferUntil) {
      intentPending = true
      flushIntent()
    }
    if (!opened) { reopenTimer.attempts = 0; reopenTimer.stop() }
  }

  onSelectedTabChanged: {
    if (isAvailable() && sessionTabRestored) service.setRememberedTab(selectedTab)
    resetScroll()
  }

  // The bar rebuilds this widget wholesale, so the tab it was showing has to
  // come back from the service instead of from this instance.
  function restoreSession() {
    if (!isAvailable()) return
    var remembered = Number(service.rememberedTab)
    if (Tabs.validIndex(remembered) && selectedTab !== remembered) selectedTab = remembered
    sessionTabRestored = true
  }

  // Open this output's copy directly: shell.summon routes to the focused
  // output, which can differ from the one the user opened before a move.
  function tryRestorePanel() {
    if (!isAvailable() || !service.panelWanted) return true
    if (service.previewBusy || service.panelEvacuationWaiting) return false
    var mine = currentScreenName()
    if (!mine) return false
    var wanted = service.panelScreenName
    if (wanted && wanted !== mine) {
      var stillConnected = false
      for (var j = 0; j < Quickshell.screens.length; j++)
        if (Quickshell.screens[j].name === wanted) { stillConnected = true; break }
      if (stillConnected) return false
    }
    if (root.opened) return true
    var widgets = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets("yakumy.station") : []
    for (var i = 0; i < widgets.length; i++) {
      if (widgets[i] && widgets[i].opened === true
          && (!wanted || typeof widgets[i].currentScreenName !== "function"
            || widgets[i].currentScreenName() === wanted)) {
        // An old copy may still be marked open while its bar slot is being
        // replaced. Keep polling until that copy goes away.
        return Date.now() >= service.panelTransferUntil
      }
    }
    showSurface()
    return true
  }

  // A rebuilt widget inherits the panel it was carrying. The bar window and
  // its screen can resolve after this component, so retry briefly.
  function requestPanelBack() {
    if (!isAvailable() || !service.panelWanted) return
    Qt.callLater(function() {
      if (!root.isAvailable() || !root.service.panelWanted) return
      if (root.tryRestorePanel()) return
      reopenTimer.attempts = 0
      reopenTimer.start()
    })
  }

  function serviceResolved() {
    sessionTabRestored = false
    flushIntent(); restoreSession(); handlePanelEvacuation(); requestPanelBack()
  }

  // Disabling a different output does not rebuild this surviving widget.
  // It still has to receive the hand-off and reopen the confirmation panel.
  Connections {
    target: root.service
    function onPanelScreenNameChanged() { root.restoreSession(); root.requestPanelBack() }
    function onPanelTransferUntilChanged() { root.requestPanelBack() }
    function onPanelWantedChanged() { root.requestPanelBack() }
    function onPanelEvacuationSerialChanged() { root.handlePanelEvacuation() }
  }
  Connections {
    target: Quickshell
    function onScreensChanged() { root.requestPanelBack() }
  }

  Timer {
    id: reopenTimer
    interval: 30
    property int attempts: 0
    onTriggered: {
      if (!root.isAvailable() || !root.service.panelWanted) { attempts = 0; return }
      if (root.tryRestorePanel()) { attempts = 0; return }
      if (attempts < 100) { attempts += 1; restart() } else attempts = 0
    }
  }

  Timer {
    id: monitorTransferAck
    // The host popup normally fades for 140 ms. We suppress that animation,
    // then still allow several Wayland commit cycles before acknowledging.
    interval: 180
    onTriggered: {
      var svc = root.service
      var serial = root.monitorTransferSerial
      var screenName = root.monitorTransferScreen
      root.monitorTransferClosing = false
      root.popoutSwitchClosing = false
      if (svc) svc.acknowledgePanelEvacuation(serial, screenName)
    }
  }

  property QtObject barFacade: QtObject {
    id: panelBarFacade
    readonly property var source: root.bar
    readonly property string desiredPosition: source ? String(source.position || "top") : "top"
    readonly property string position: {
      var window = root.anchorWindow
      return PanelPosition.stableBarPosition(root.stablePanelBarPosition,
        desiredPosition, window ? window.width : 0, window ? window.height : 0,
        source ? source.barSize + Style.gapsOut : 0)
    }
    readonly property real barSize: PanelPosition.verticalBarPosition(position)
      ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
    readonly property var activePopout: source ? source.activePopout : null
    readonly property var clickTargets: source ? source.clickTargets : []

    onPositionChanged: root.stablePanelBarPosition = position

    function requestPopout(owner) {
      if (source && typeof source.requestPopout === "function") source.requestPopout(owner)
    }
    function releasePopout(owner) {
      if (source && typeof source.releasePopout === "function") source.releasePopout(owner)
    }
    function targetBelongsToWindow(target, window) {
      return source && typeof source.targetBelongsToWindow === "function"
        ? source.targetBelongsToWindow(target, window) : false
    }
  }

  function probeEvacuation(startingSerial) {
    evacuationProbe.attempts = 0
    evacuationProbe.startingSerial = startingSerial
    evacuationProbe.restart()
  }
}
