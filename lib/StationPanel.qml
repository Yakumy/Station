import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell
import qs.Ui as Ui
import qs.Commons
import "Model.js" as Model
import "Binds.js" as Binds
import "PanelPosition.js" as PanelPosition
import "." as Station

Ui.Panel {
  id: root
  moduleName: "yakumy.station"
  manageIpc: false

  readonly property var directService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("yakumy.station") : null
  // Supplied by Panel.qml so service and widget share the same script URL.
  property var bridgeCurrent: function() { return null }
  property var bridgeApi: null
  property var bridgeSnapshot: null
  property string bridgeSnapshotText: ""
  readonly property var service: directService || (bridgeSnapshot ? bridgeProxy : null)
  property int selectedTab: 0
  property bool sessionTabRestored: false
  // A cross-axis bar move reconfigures the bar's layer surface. During that
  // Wayland transition QsWindow can briefly stop reporting the anchor screen,
  // which made KeyboardPanel follow the transient null and remap even though
  // this StationPanel instance survived. Retain the real screen object while
  // the panel is open; the card geometry can continue following the same live
  // anchor item without moving the panel surface between outputs.
  property var retainedPanelScreen: null
  // KeyboardPanel normally reads bar.position immediately, but a cross-axis
  // layer-shell change publishes that value before the bar window has swapped
  // from full-height/thin to full-width/thin (or vice versa). Keep the last
  // geometrically valid edge until the anchor window reports the new axis.
  property string stablePanelBarPosition: "top"
  property int stationNumber: service ? service.currentStation : 1
  readonly property string selectedDisplayName: {
    if (!service) return ""
    var displays = service.displayDraft
    var remembered = service.rememberedDisplayName
    for (var i = 0; i < displays.length; i++)
      if (displays[i].name === remembered) return remembered
    return displays.length ? displays[0].name : ""
  }
  property int brightness: 0
  property bool brightnessAvailable: false
  readonly property bool brightnessLoading: brightnessRead.running
  property var pendingBrightnessRequest: null
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1
  property int queuedTextSize: -1
  property bool monitorTransferClosing: false
  property int monitorTransferSerial: 0
  property string monitorTransferScreen: ""
  property int handledEvacuationSerial: 0
  property string editingBindingId: ""
  property var editingModifiers: ({ SUPER: false, CTRL: false, ALT: false, SHIFT: false })
  property string editingKey: ""
  readonly property string pluginVersion: service && service.manifest && service.manifest.version ? String(service.manifest.version) : ""
  readonly property real desiredPanelWidth: Style.space(996)

  // Station design tokens (docs/v2/DESIGN-SYSTEM.md). Component code reads
  // these; nothing below this block hardcodes a colour, radius or step.
  //
  // 4px grid. Only these steps exist; pick the smallest that reads clearly.
  readonly property real space1: Style.space(4)
  readonly property real space2: Style.space(8)
  readonly property real space3: Style.space(12)
  readonly property real space4: Style.space(16)
  readonly property real space5: Style.space(20)
  readonly property real space6: Style.space(24)

  // Regions share one outer rhythm: 24px horizontal, 20px vertical.
  readonly property real regionPadH: space6
  readonly property real regionPadV: space5

  readonly property color textPrimary: Color.popups.text
  readonly property color textDim: Qt.darker(Color.popups.text, 1.4)

  readonly property real disabledOpacity: 0.6
  readonly property real tabUnderline: Style.space(2)
  readonly property real controlHeight: Style.spacing.controlHeight

  readonly property int conflictCount: service
    ? service.bindStatuses.filter(function(item) { return item.status === "conflict" }).length : 0
  readonly property var selectedDisplay: {
    if (!service) return null
    for (var i = 0; i < service.displayDraft.length; i++)
      if (service.displayDraft[i].name === selectedDisplayName) return service.displayDraft[i]
    return service.displayDraft.length ? service.displayDraft[0] : null
  }
  readonly property string modeValue: service && service.draftMode === "single"
    ? "single:" + service.draftSingleTarget : (service ? service.draftMode : "extend")
  readonly property var modeOptions: {
    var options = [{ value: "extend", label: "Extend" }, { value: "mirror", label: "Mirror" }]
    if (!service) return options
    service.displayDraft.forEach(function(display) {
      options.push({ value: "single:" + display.name,
        label: "Single · " + display.name })
    })
    return options
  }
  readonly property var bindingGroups: [
    { label: "Switch to station", combo: "SUPER + 1 … 0", ids: root.bindingIds("switch-", 10) },
    { label: "Move window to station", combo: "SUPER + SHIFT + 1 … 0", ids: root.bindingIds("send-", 10) },
    { label: "Move silently (no follow)", combo: "SUPER + SHIFT + ALT + 1 … 0", ids: root.bindingIds("silent-", 10) },
    { label: "Station to the left", combo: "SUPER + CTRL + ←", ids: ["go-left"] },
    { label: "Station to the right", combo: "SUPER + CTRL + →", ids: ["go-right"] },
    { label: "Move across monitors and stations", combo: "SHIFT + CTRL + SUPER + ← → ↑ ↓",
      ids: ["shift-left", "shift-right", "shift-up", "shift-down"] }
  ]

  Station.BarServiceProxy {
    id: bridgeProxy
    snapshot: root.bridgeSnapshot
    api: root.bridgeApi
  }

  Timer {
    interval: root.opened ? 250 : 1000
    running: !root.directService
    repeat: true
    triggeredOnStart: true
    onTriggered: root.syncBridge()
  }

  function syncBridge() {
    // The trusted bar keeps its existing live-service path without polling.
    if (directService) return
    var api = bridgeCurrent()
    if (!api) {
      bridgeApi = null
      bridgeSnapshot = null
      bridgeSnapshotText = ""
      return
    }
    var next = api.snapshot()
    bridgeApi = api
    var serialized = JSON.stringify(next)
    if (serialized !== bridgeSnapshotText) {
      bridgeSnapshotText = serialized
      bridgeSnapshot = next
    }
  }

  function bindingIds(prefix, count) {
    var ids = []
    for (var i = 1; i <= count; i++) ids.push(prefix + i)
    return ids
  }

  function bindingForId(id) {
    if (!service) return null
    for (var i = 0; i < service.bindStatuses.length; i++)
      if (service.bindStatuses[i].id === id) return service.bindStatuses[i]
    return null
  }

  function conflictsFor(ids) {
    var conflicts = []
    for (var i = 0; i < ids.length; i++) {
      var binding = bindingForId(ids[i])
      if (binding && binding.status === "conflict") conflicts.push(binding)
    }
    return conflicts
  }

  function groupStatus(ids) {
    var priority = { conflict: 4, unverified: 3, replacement: 2, free: 1 }
    var result = "free", score = 0
    for (var i = 0; i < ids.length; i++) {
      var binding = bindingForId(ids[i])
      var status = binding ? binding.status : "unverified"
      if ((priority[status] || 0) > score) { result = status; score = priority[status] || 0 }
    }
    return result
  }

  function statusLabel(status) {
    return status === "replacement" ? "REPLACES DEFAULT" : String(status || "unverified").toUpperCase()
  }

  function roleName(display) {
    if (!display || !display.enabled || !service) return "Off"
    var role = service.roleOf(display.name)
    return ["Primary", "Secondary", "Third"][role] || "Lane " + display.lane
  }

  function selectDisplay(name) {
    if (!service || !service.displayDraft.some(function(display) { return display.name === name })) return
    service.setRememberedDisplayName(name)
  }

  onSelectedDisplayNameChanged: {
    brightnessAvailable = false
    refreshBrightness()
  }

  function changeMode(value) {
    if (!service || !service.draftEditable) return
    if (value.indexOf("single:") === 0) service.setModeValue("single", value.substring(7))
    else service.setModeValue(value, "")
  }

  function beginBindingEdit(binding) {
    var normalized = Binds.normalize(binding.combo).split("+")
    editingModifiers = {
      SUPER: normalized.indexOf("SUPER") !== -1,
      CTRL: normalized.indexOf("CTRL") !== -1,
      ALT: normalized.indexOf("ALT") !== -1,
      SHIFT: normalized.indexOf("SHIFT") !== -1
    }
    editingKey = normalized[normalized.length - 1] || ""
    editingBindingId = binding.id
  }

  function toggleEditingModifier(name) {
    var next = Object.assign({}, editingModifiers)
    next[name] = !next[name]
    editingModifiers = next
  }

  function applyBindingEdit() {
    if (!service || !editingBindingId || !editingKey.trim()) return
    var parts = []
    ;["SUPER", "CTRL", "ALT", "SHIFT"].forEach(function(mod) {
      if (editingModifiers[mod]) parts.push(mod)
    })
    parts.push(editingKey.trim())
    if (service.setBinding(editingBindingId, parts.join(" + ")) === "ok") editingBindingId = ""
  }

  function refreshBrightness(name) {
    var target = name || selectedDisplayName
    if (!target || brightnessRead.running) return
    brightnessRead.monitorName = target
    brightnessRead.command = ["omarchy-brightness-display", "--monitor", target]
    brightnessRead.running = true
  }

  function queueBrightness(value) {
    if (!brightnessAvailable || !selectedDisplayName) return
    brightnessDebounce.pending = Math.round(value)
    brightnessDebounce.monitorName = selectedDisplayName
    brightnessDebounce.restart()
  }

  function nearestTextIndex(px) {
    var best = 0, distance = Infinity
    for (var i = 0; i < textSizeStops.length; i++) {
      var next = Math.abs(textSizeStops[i] - px)
      if (next < distance) { best = i; distance = next }
    }
    return best
  }

  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextIndex(Style.font.baseSize)
  }

  function displayedTextSize() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSizeIndex(index) {
    if (index < 0 || index >= textSizeStops.length) return
    if (index === currentTextIndex()) return
    textSizePreviewIndex = index
    if (textSizeWrite.running) { queuedTextSize = textSizeStops[index]; return }
    textSizeWrite.command = ["omarchy-display-text-size", String(textSizeStops[index])]
    textSizeWrite.running = true
  }

  function setBrightness(value, monitorName) {
    if (!monitorName) return
    var level = Math.max(1, Math.min(100, Math.round(value)))
    if (monitorName === selectedDisplayName) brightness = level
    if (brightnessWrite.running) {
      pendingBrightnessRequest = { value: level, monitorName: monitorName }
      return
    }
    brightnessWrite.command = ["omarchy", "brightness", "display", "--no-osd", "--monitor",
      monitorName, level + "%"]
    brightnessWrite.running = true
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
    var window = panel.anchorWindow
    if (window && window.screen) return window.screen
    return service ? screenByName(service.panelScreenName) : null
  }

  function retainCurrentPanelScreen() {
    var window = panel.anchorWindow
    var screen = window && window.screen ? window.screen : null
    if (!screen && service) screen = screenByName(service.panelScreenName)
    if (screen) retainedPanelScreen = screen
  }

  // An explicit dismissal wins even if a bar rebuild is in progress.
  function close() {
    if (service) {
      service.setPanelTransferUntil(0)
      // The proxy may still show the old transfer deadline until its next poll.
      // Record explicit dismissal now instead of relying on onOpenedChanged.
      service.setPanelWanted(false)
      service.setRememberedTab(0)
    }
    controller.hide()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    controller.hide()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function closeForMonitorTransfer(serial, screenName) {
    monitorTransferClosing = true
    monitorTransferSerial = serial
    monitorTransferScreen = screenName
    // Skip the 140 ms fade so the focus grab and layer surface are gone well
    // before Hyprland receives the monitor-disable rule.
    popoutSwitchClosing = true
    controller.hide()
    monitorTransferAck.restart()
  }

  function handlePanelEvacuation() {
    if (!service || !service.panelEvacuationWaiting) return
    var serial = Number(service.panelEvacuationSerial)
    if (!serial || serial <= handledEvacuationSerial) return
    var mine = currentScreenName()
    if (!mine || mine !== service.panelEvacuationFrom) return
    handledEvacuationSerial = serial
    closeForMonitorTransfer(serial, mine)
  }

  function flushIntent() {
    if (!service || !intentPending) return
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
      refreshBrightness()
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
    } else if (!service || Date.now() >= service.panelTransferUntil) {
      intentPending = true
      flushIntent()
    }
    if (!opened) { reopenTimer.attempts = 0; reopenTimer.stop() }
  }

  onSelectedTabChanged: if (service && sessionTabRestored) service.setRememberedTab(selectedTab)

  // The bar rebuilds this widget wholesale, so the tab it was showing has to
  // come back from the service instead of from this instance.
  function restoreSession() {
    if (!service) return
    var remembered = Number(service.rememberedTab)
    if (remembered >= 0 && remembered <= 4 && selectedTab !== remembered) selectedTab = remembered
    sessionTabRestored = true
  }

  // Open this output's copy directly: shell.summon routes to the focused
  // output, which can differ from the one the user opened before a move.
  function tryRestorePanel() {
    if (!service || !service.panelWanted) return true
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
    root.open()
    return true
  }

  // A rebuilt widget inherits the panel it was carrying. The bar window and
  // its screen can resolve after this component, so retry briefly.
  function requestPanelBack() {
    if (!service || !service.panelWanted) return
    Qt.callLater(function() {
      if (!root.service || !root.service.panelWanted) return
      if (root.tryRestorePanel()) return
      reopenTimer.attempts = 0
      reopenTimer.start()
    })
  }

  onServiceChanged: {
    sessionTabRestored = false
    flushIntent(); restoreSession(); handlePanelEvacuation(); requestPanelBack()
  }
  Component.onCompleted: { syncBridge(); flushIntent(); restoreSession(); handlePanelEvacuation(); requestPanelBack() }

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
      if (!root.service || !root.service.panelWanted) { attempts = 0; return }
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

  Process {
    id: brightnessRead
    property string monitorName: ""
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: brightnessRead.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: {
      if (monitorName !== root.selectedDisplayName) {
        root.refreshBrightness()
        return
      }
      var first = captured.split("\n")[0].trim()
      root.brightnessAvailable = exitCode === 0 && first !== "" && first !== "unavailable" && isFinite(Number(first))
      root.brightness = root.brightnessAvailable ? Number(first) : 0
    }
  }

  Timer {
    id: brightnessDebounce
    property int pending: 0
    property string monitorName: ""
    interval: 180
    onTriggered: root.setBrightness(pending, monitorName)
  }

  Process {
    id: brightnessWrite
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      var pending = root.pendingBrightnessRequest
      root.pendingBrightnessRequest = null
      if (pending) root.setBrightness(pending.value, pending.monitorName)
    }
  }

  Process {
    id: textSizeWrite
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      if (exitCode !== 0) root.textSizePreviewIndex = -1
      if (root.queuedTextSize >= 0) {
        var next = root.queuedTextSize
        root.queuedTextSize = -1
        command = ["omarchy-display-text-size", String(next)]
        running = true
      }
    }
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextIndex(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }

  implicitWidth: barControls.implicitWidth
  implicitHeight: barControls.implicitHeight

  // Popout coordinator identity stays off the bar slot root so the host's
  // open-panel dot does not center across logo + S1. The underline under
  // the logo is drawn by the logo button itself.
  //
  // KeyboardPanel.close() forwards to owner.close(), and `owner` is this
  // object, so these must call straight through to `root`. Do NOT introduce a
  // property or local named `panel` here: `id: panel` below belongs to the
  // KeyboardPanel, and that name wins, so `panel.close()` would call
  // KeyboardPanel.close() again and recurse until the stack blows. The
  // recursion threw a RangeError that left outside-click dismissal dead --
  // clicking the icon still worked because root.toggle() bypasses this object.
  QtObject {
    id: popoutOwner
    readonly property bool popoutSwitchClosing: root.popoutSwitchClosing
    function close() { root.close() }
    function closeForPopoutSwitch() { root.closeForPopoutSwitch() }
  }

  // Delay only KeyboardPanel's view of the bar edge. The real bar and its
  // modules reflow immediately, while the popout keeps using one internally
  // consistent position/window-geometry pair throughout the surface remap.
  QtObject {
    id: panelBarFacade
    readonly property var source: root.bar
    readonly property string desiredPosition: source ? String(source.position || "top") : "top"
    readonly property string position: {
      var window = panel.anchorWindow
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

  Station.StationBar {
    id: barControls
    bar: root.bar
    stationNumber: root.stationNumber
    opened: root.opened
    onPressed: root.toggle()
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: barControls.anchorItem
    owner: popoutOwner
    bar: panelBarFacade
    // Override KeyboardPanel's default `anchorWindow.screen` binding. That
    // screen is stable for same-axis moves but can be transient during the
    // layer-shell anchor/size change required by a horizontal↔vertical move.
    screen: root.currentPanelScreen()
    centerOnBar: root.service && root.service.config.panelPosition === "center"
    gap: centerOnBar ? PanelPosition.centerGap(barPos, screenW, screenH, barW, barH,
      root.desiredPanelWidth, (barPos === "top" || barPos === "bottom")
        ? content.implicitHeight + verticalContentInset : 0,
      margin, Style.gapsOut) : Style.gapsOut
    open: root.opened
    focusTarget: keyCatcher
    padding: 0
    // The reference's wider two-column canvas is approximately 830 logical
    // pixels at the current font scale. The host still caps this to the screen.
    contentWidth: panel.fittedContentWidth(root.desiredPanelWidth)
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.selectedTab = (root.selectedTab + (direction > 0 ? 1 : 4)) % 5
      }

      Column {
        id: content
        x: 0
        width: parent.width
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(67)
          Station.StationMark {
            id: logo
            width: Style.space(34)
            height: Style.space(34)
            tint: root.bar ? root.bar.foreground : Color.bar.text
            anchors.left: parent.left
            anchors.leftMargin: root.regionPadH
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            anchors.left: logo.right
            anchors.leftMargin: root.space3
            anchors.verticalCenter: logo.verticalCenter
            text: "Station"
            color: root.textPrimary
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }
        }

        Item {
          width: parent.width
          height: root.controlHeight + root.space1
          Row {
            id: tabs
            anchors.left: parent.left
            anchors.leftMargin: root.regionPadH
            anchors.bottom: parent.bottom
            height: parent.height
            Repeater {
              model: ["Displays", "Bar", "Wallpaper", "Keybindings", "Settings"]
              delegate: Item {
                id: tab
                required property int index
                required property string modelData
                readonly property bool conflicted: index === 3 && root.conflictCount > 0
                height: tabs.height
                // 28px between tabs; the row's left margin carries the 24px
                // region inset so the first tab still aligns with the logo.
                width: tabLabel.implicitWidth + root.space4 + root.space3
                  + (conflicted ? badge.width + root.space1 : 0)
                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  anchors.horizontalCenterOffset: tab.conflicted
                    ? -(badge.width + root.space1) / 2 : 0
                  text: tab.modelData
                  // Selection is carried by the accent rule underneath, so the
                  // label only steps between the dim and full text tokens.
                  color: tab.conflicted ? Color.urgent
                    : (root.selectedTab === tab.index ? root.textPrimary : root.textDim)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Rectangle {
                  id: badge
                  visible: tab.conflicted
                  anchors.left: tabLabel.right
                  anchors.leftMargin: root.space1
                  anchors.verticalCenter: tabLabel.verticalCenter
                  width: Math.max(root.space4, badgeText.implicitWidth + root.space2)
                  height: root.space4
                  color: Color.urgent
                  radius: Style.cornerRadius
                  Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.conflictCount
                    color: Color.popups.background
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.weight: Font.DemiBold
                  }
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: root.tabUnderline
                  color: tab.conflicted ? Color.urgent : Color.accent
                  visible: root.selectedTab === tab.index
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedTab = tab.index
                }
              }
            }
          }
          Row {
            visible: root.selectedTab === 0
            anchors.right: parent.right
            anchors.rightMargin: root.regionPadH
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.space3
            Station.InlineDropdown {
              prefix: "Direction: "
              value: root.service ? root.service.config.direction : "ltr"
              options: [{ value: "ltr", label: "LTR" }, { value: "rtl", label: "RTL" },
                { value: "ttb", label: "TTB" }, { value: "btt", label: "BTT" }]
              foreground: root.textDim
              onChanged: function(value) { if (root.service) root.service.setDirectionValue(value) }
            }
            Station.InlineDropdown {
              prefix: "Mode: "
              value: root.modeValue
              options: root.modeOptions
              popupMinWidth: root.space6 * 7
              popupAlignRight: true
              foreground: root.textDim
              onChanged: function(value) { root.changeMode(value) }
            }
          }
        }

        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }
        Station.DisplaysTab { visible: root.selectedTab === 0; width: parent.width; panelRoot: root }
        Station.BarTab { visible: root.selectedTab === 1; width: parent.width; panelRoot: root }
        Station.WallpaperTab { visible: root.selectedTab === 2; width: parent.width; panelRoot: root }
        Station.KeybindingsTab { visible: root.selectedTab === 3; width: parent.width; panelRoot: root }
        Station.SettingsTab { visible: root.selectedTab === 4; width: parent.width; panelRoot: root }
      }
    }
  }
}
