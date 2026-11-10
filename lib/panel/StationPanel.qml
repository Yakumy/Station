import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui as Ui
import qs.Commons
import "../displays/Model.js" as Model
import "Tabs.js" as Tabs
import "PanelPosition.js" as PanelPosition
import "../bars" as Bars
import "../displays" as Displays
import "../keybindings" as Keys
import "../stations" as Stations
import "." as PanelUi
import "../wallpaper" as WallpaperUi
import "../windows" as WindowsUi

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
  property alias selectedTab: session.selectedTab
  popoutSwitchClosing: session.popoutSwitchClosing
  property int stationNumber: service ? service.currentStation : 1
  readonly property string selectedDisplayName: {
    if (!service) return ""
    var displays = service.displayDraft
    var remembered = service.rememberedDisplayName
    for (var i = 0; i < displays.length; i++)
      if (displays[i].name === remembered) return remembered
    return displays.length ? displays[0].name : ""
  }
  readonly property string pluginVersion: service && service.manifest && service.manifest.version ? String(service.manifest.version) : ""
  readonly property real desiredPanelWidth: Style.space(996)
  readonly property real desiredPanelHeight: Style.space(620)

  // Station design tokens (docs/v2/DESIGN-SYSTEM.md). Component code reads
  // these; nothing below this block hardcodes a colour, radius or step.
  //
  // 4px grid. Only these steps exist; pick the smallest that reads clearly.
  QtObject {
    id: panelTokens
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

  }
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

  QtObject {
    id: panelIntent
    function acknowledgePanelEvacuation(serial, screenName) { return root.service ? root.service.acknowledgePanelEvacuation(serial, screenName) : undefined }
    function displayEnabled(name) { return root.service ? root.service.displayEnabled(name) : undefined }
    readonly property var panelEvacuationFrom: root.service ? root.service.panelEvacuationFrom : ""
    readonly property var panelEvacuationReleases: root.service ? root.service.panelEvacuationReleases : []
    readonly property var panelEvacuationSerial: root.service ? root.service.panelEvacuationSerial : 0
    readonly property var panelEvacuationWaiting: root.service ? root.service.panelEvacuationWaiting : null
    readonly property var panelScreenName: root.service ? root.service.panelScreenName : ""
    readonly property var panelTransferUntil: root.service ? root.service.panelTransferUntil : 0
    readonly property var panelWanted: root.service ? root.service.panelWanted : null
    readonly property var previewBusy: root.service ? root.service.previewBusy : null
    readonly property var rememberedTab: root.service ? root.service.rememberedTab : 0
    function setPanelScreenName(value) { return root.service ? root.service.setPanelScreenName(value) : undefined }
    function setPanelTransferUntil(value) { return root.service ? root.service.setPanelTransferUntil(value) : undefined }
    function setPanelWanted(value) { return root.service ? root.service.setPanelWanted(value) : undefined }
    function setRememberedTab(value) { return root.service ? root.service.setRememberedTab(value) : undefined }
  }

  QtObject {
    id: displaysTabPort
    function applyDisplaySetting(name, key, value) { return root.service ? root.service.applyDisplaySetting(name, key, value) : undefined }
    readonly property var displayDraft: root.service ? root.service.displayDraft : []
    function displayEnabled(name) { return root.service ? root.service.displayEnabled(name) : undefined }
    readonly property var draftEditable: root.service ? root.service.draftEditable : null
    function keepPreview() { return root.service ? root.service.keepPreview() : undefined }
    readonly property var layoutError: root.service ? root.service.layoutError : null
    readonly property var previewBusy: root.service ? root.service.previewBusy : null
    function previewLayout() { return root.service ? root.service.previewLayout() : undefined }
    readonly property var previewSeconds: root.service ? root.service.previewSeconds : null
    function revertPreview(reason) { return root.service ? root.service.revertPreview(reason) : undefined }
    function roleOf(name) { return root.service ? root.service.roleOf(name) : undefined }
    function setDisplayEnabled(name, enabled) { return root.service ? root.service.setDisplayEnabled(name, enabled) : undefined }
    function setDisplayPosition(name, x, y) { return root.service ? root.service.setDisplayPosition(name, x, y) : undefined }
    function setDisplayTransform(name, value) { return root.service ? root.service.setDisplayTransform(name, value) : undefined }
    readonly property var state: root.service ? root.service.state : null
    function swapRole(name, roleIndex) { return root.service ? root.service.swapRole(name, roleIndex) : undefined }
  }

  QtObject {
    id: workspacesTabPort
    readonly property var config: root.service ? root.service.config : ({})
    readonly property var displayDraft: root.service ? root.service.displayDraft : []
    readonly property var workspaceTarget: root.service ? root.service.workspaceTarget : ({ outputs: [] })
    readonly property var state: root.service ? root.service.state : null
    function setSetting(name, value) { return root.service ? root.service.setSetting(name, value) : undefined }
  }

  QtObject {
    id: barTabPort
    readonly property var displayDraft: root.service ? root.service.displayDraft : []
    function displayEnabled(name) { return root.service ? root.service.displayEnabled(name) : undefined }
    function monitorBar(name) { return root.service ? root.service.monitorBar(name) : undefined }
    function monitorBarMaximumContent(name) { return root.service ? root.service.monitorBarMaximumContent(name) : undefined }
    function monitorBarMaximumHeight(name) { return root.service ? root.service.monitorBarMaximumHeight(name) : undefined }
    function monitorBarMinimum(name) { return root.service ? root.service.monitorBarMinimum(name) : undefined }
    function setMonitorBarBackground(name, background) { return root.service ? root.service.setMonitorBarBackground(name, background) : undefined }
    function setMonitorBarContentSize(name, contentSize) { return root.service ? root.service.setMonitorBarContentSize(name, contentSize) : undefined }
    function setMonitorBarEnabled(name, enabled) { return root.service ? root.service.setMonitorBarEnabled(name, enabled) : undefined }
    function setMonitorBarHeight(name, height) { return root.service ? root.service.setMonitorBarHeight(name, height) : undefined }
    function setMonitorBarPosition(name, position) { return root.service ? root.service.setMonitorBarPosition(name, position) : undefined }
    function setMonitorBarStyle(name, style) { return root.service ? root.service.setMonitorBarStyle(name, style) : undefined }
    function setMonitorBarWidth(name, width) { return root.service ? root.service.setMonitorBarWidth(name, width) : undefined }
  }

  QtObject {
    id: windowsTabPort
    readonly property var config: root.service ? root.service.config : ({})
    readonly property var displayDraft: root.service ? root.service.displayDraft : []
    function displayEnabled(name) { return root.service ? root.service.displayEnabled(name) : undefined }
    function monitorBar(name) { return root.service ? root.service.monitorBar(name) : undefined }
    function monitorBarMaximumHeight(name) { return root.service ? root.service.monitorBarMaximumHeight(name) : undefined }
    function monitorBarMinimum(name) { return root.service ? root.service.monitorBarMinimum(name) : undefined }
    function setWindowSetting(key, value) { return root.service ? root.service.setWindowSetting(key, value) : undefined }
    readonly property var windowSettingsBusy: root.service ? root.service.windowSettingsBusy : null
  }

  QtObject {
    id: keybindingsTabPort
    function approveBinding(combo) { return root.service ? root.service.approveBinding(combo) : undefined }
    readonly property var bindStatuses: root.service ? root.service.bindStatuses : []
    function setBinding(id, combo) { return root.service ? root.service.setBinding(id, combo) : undefined }
  }

  QtObject {
    id: settingsTabPort
    function acquireStockLeases() { return root.service ? root.service.acquireStockLeases() : undefined }
    readonly property var config: root.service ? root.service.config : ({})
    readonly property var displayWidgetEnabled: root.service ? root.service.displayWidgetEnabled : null
    function setSetting(name, value) { return root.service ? root.service.setSetting(name, value) : undefined }
  }

  Displays.DisplayControls {
    id: displayControls
    selectedDisplayName: root.selectedDisplayName
  }
  PanelUi.PanelSession {
    id: session
    service: panelIntent
    isAvailable: function() { return !!root.service }
    directService: root.directService
    bridgeApi: root.bridgeApi
    bar: root.bar
    anchorWindow: panel.anchorWindow
    opened: root.opened
    hideSurface: function() { root.controller.hide() }
    showSurface: function() { root.open() }
    syncBridge: function() { root.syncBridge() }
    refreshControls: function() { displayControls.refreshBrightness() }
    resetScroll: function() { if (tabScroll.contentItem) tabScroll.contentItem.contentY = 0 }
    setPeerSurfacesVisible: function(names, visible) { return root.setPeerSurfacesVisible(names, visible) }
    primeFocus: function() { panel.beginFocusPrime() }
  }
  // KeyboardPanel keeps its per-output dismiss surfaces private, in a Variants among
  // its children. False when a host version no longer has it, so the caller closes.
  function setPeerSurfacesVisible(names, visible) {
    var children = panel.data
    for (var i = 0; children && i < children.length; i++) {
      var instances = children[i] ? children[i].instances : undefined
      if (!instances || !instances.length) continue
      for (var j = 0; j < instances.length; j++) {
        var surface = instances[j]
        if (surface.screen && names.indexOf(String(surface.screen.name || "")) !== -1) surface.visible = visible
      }
      return true
    }
    return false
  }
  function currentScreenName() { return session.currentScreenName() }
  function close() { session.close() }
  function closeForPopoutSwitch() { session.closeForPopoutSwitch() }
  onServiceChanged: if (session) session.serviceResolved()
  Component.onCompleted: { syncBridge(); session.flushIntent(); session.restoreSession(); session.handlePanelEvacuation(); session.requestPanelBack() }

  PanelUi.BarServiceProxy {
    id: bridgeProxy
    snapshot: root.bridgeSnapshot
    api: root.bridgeApi
    onSnapshotRefreshRequested: root.syncBridge()
  }

  Timer {
    interval: root.opened || (root.service && root.service.config.stationAppsMode !== "hide") ? 150 : 1000
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
    // Snapshot-derived property notifications may arrive in any order.
    // Check the complete request after every snapshot, not only its serial.
    session.handlePanelEvacuation()
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

  function changeMode(value) {
    if (!service || !service.draftEditable) return
    var startingSerial = Number(service.panelEvacuationSerial) || 0
    var result = value.indexOf("single:") === 0
      ? service.setModeValue("single", value.substring(7))
      : service.setModeValue(value, "")
    if (result === "started") {
      session.probeEvacuation(startingSerial)
    }
    return result
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
  Bars.StationBar {
    id: barControls
    bar: root.bar
    stationNumber: root.stationNumber
    appsMode: root.service ? root.service.config.stationAppsMode : "hide"
    stationApps: root.service ? root.service.openApps : ({})
    workspaceMap: root.service ? root.service.workspaceMap : null
    workspaceApps: root.service ? root.service.workspaceApps : ({})
    indicatorStyle: root.service ? root.service.config.indicatorStyle || "prefixed" : "prefixed"
    showWorkspaceIds: !!root.service && root.service.config.hideNative === false
    stationCount: root.service ? Number(root.service.config.minStations) || 3 : 3
    onStationSelected: function(number) {
      if (root.service) root.service.showWorkspace(String(number), barControls.screenName)
    }
    opened: root.opened
    onPressed: root.toggle()
  }

  Ui.KeyboardPanel {
    id: panel
    objectName: "stationPanelWindow"
    anchorItem: barControls.anchorItem
    owner: popoutOwner
    bar: session.barFacade
    // Override KeyboardPanel's default `anchorWindow.screen` binding. That
    // screen is stable for same-axis moves but can be transient during the
    // layer-shell anchor/size change required by a horizontal↔vertical move.
    screen: session.currentPanelScreen()
    centerOnBar: root.service && root.service.config.panelPosition === "center"
    gap: centerOnBar ? PanelPosition.centerGap(barPos, screenW, screenH, barW, barH,
      root.desiredPanelWidth, (barPos === "top" || barPos === "bottom")
        ? root.desiredPanelHeight + verticalContentInset : 0,
      margin, Style.gapsOut) : Style.gapsOut
    open: root.opened
    focusTarget: keyCatcher
    padding: 0
    // The reference's wider two-column canvas is approximately 830 logical
    // pixels at the current font scale. The host still caps this to the screen.
    contentWidth: panel.fittedContentWidth(root.desiredPanelWidth)
    contentHeight: panel.fittedContentHeight(root.desiredPanelHeight)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (dy && tabScroll.contentItem) {
          var limit = Math.max(0, tabScroll.contentHeight - tabScroll.height)
          tabScroll.contentItem.contentY = Math.max(0,
            Math.min(limit, tabScroll.contentItem.contentY + dy * panelTokens.controlHeight))
        }
      }
      onTabRequested: function(direction) {
        root.selectedTab = Tabs.next(root.selectedTab, direction)
      }

      Column {
        id: content
        x: 0
        width: parent.width
        height: parent.height
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(67)
          PanelUi.StationMark {
            id: logo
            width: Style.space(34)
            height: Style.space(34)
            tint: root.bar ? root.bar.foreground : Color.bar.text
            anchors.left: parent.left
            anchors.leftMargin: panelTokens.regionPadH
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            anchors.left: logo.right
            anchors.leftMargin: panelTokens.space3
            anchors.verticalCenter: logo.verticalCenter
            text: "Station"
            color: panelTokens.textPrimary
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }
        }

        Item {
          width: parent.width
          height: panelTokens.controlHeight + panelTokens.space1
          Row {
            id: tabs
            anchors.left: parent.left
            anchors.leftMargin: panelTokens.regionPadH
            anchors.bottom: parent.bottom
            height: parent.height
            Repeater {
              model: Tabs.labels()
              delegate: Item {
                id: tab
                required property int index
                required property string modelData
                readonly property bool conflicted: index === Tabs.index("keybindings") && root.conflictCount > 0
                height: tabs.height
                // 28px between tabs; the row's left margin carries the 24px
                // region inset so the first tab still aligns with the logo.
                width: tabLabel.implicitWidth + panelTokens.space4 + panelTokens.space3
                  + (conflicted ? badge.width + panelTokens.space1 : 0)
                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  anchors.horizontalCenterOffset: tab.conflicted
                    ? -(badge.width + panelTokens.space1) / 2 : 0
                  text: tab.modelData
                  // Selection is carried by the accent rule underneath, so the
                  // label only steps between the dim and full text panelTokens.
                  color: tab.conflicted ? Color.urgent
                    : (root.selectedTab === tab.index ? panelTokens.textPrimary : panelTokens.textDim)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Rectangle {
                  id: badge
                  visible: tab.conflicted
                  anchors.left: tabLabel.right
                  anchors.leftMargin: panelTokens.space1
                  anchors.verticalCenter: tabLabel.verticalCenter
                  width: Math.max(panelTokens.space4, badgeText.implicitWidth + panelTokens.space2)
                  height: panelTokens.space4
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
                  height: panelTokens.tabUnderline
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
            visible: root.selectedTab === Tabs.index("displays")
            anchors.right: parent.right
            anchors.rightMargin: panelTokens.regionPadH
            anchors.verticalCenter: parent.verticalCenter
            spacing: panelTokens.space3
            PanelUi.InlineDropdown {
              prefix: "Direction: "
              value: root.service ? root.service.config.direction : "ltr"
              options: [{ value: "ltr", label: "LTR" }, { value: "rtl", label: "RTL" },
                { value: "ttb", label: "TTB" }, { value: "btt", label: "BTT" }]
              foreground: panelTokens.textDim
              onChanged: function(value) { if (root.service) root.service.setDirectionValue(value) }
            }
            PanelUi.InlineDropdown {
              prefix: "Mode: "
              value: root.modeValue
              options: root.modeOptions
              popupMinWidth: panelTokens.space6 * 7
              popupAlignRight: true
              foreground: panelTokens.textDim
              onChanged: function(value) { root.changeMode(value) }
            }
          }
        }

        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }
        ScrollView {
          id: tabScroll
          objectName: "stationTabScroll"
          width: parent.width
          height: Math.max(0, content.height - y - (previewStrip.visible ? previewStrip.height : 0))
          contentWidth: availableWidth
          contentHeight: tabContent.implicitHeight
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          ScrollBar.vertical.policy: contentHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          Binding {
            target: tabScroll.contentItem
            property: "interactive"
            value: tabScroll.contentHeight > tabScroll.height
          }
          Column {
            id: tabContent
            objectName: "stationTabContent"
            width: tabScroll.availableWidth
            Displays.DisplaysTab { visible: root.selectedTab === Tabs.index("displays"); width: parent.width; tokens: panelTokens; service: root.service ? displaysTabPort : null; selectedDisplay: root.selectedDisplay; selectedDisplayName: root.selectedDisplayName; bar: root.bar; selectDisplay: function(name) { root.selectDisplay(name) }; controls: displayControls }
            Stations.WorkspacesTab { visible: root.selectedTab === Tabs.index("workspaces"); width: parent.width; tokens: panelTokens; service: root.service ? workspacesTabPort : null }
            Bars.BarTab { visible: root.selectedTab === Tabs.index("bar"); width: parent.width; tokens: panelTokens; service: root.service ? barTabPort : null; selectedDisplay: root.selectedDisplay; bar: root.bar; selectDisplay: function(name) { root.selectDisplay(name) } }
            WindowsUi.WindowsTab { visible: root.selectedTab === Tabs.index("windows"); width: parent.width; tokens: panelTokens; service: root.service ? windowsTabPort : null; selectedDisplay: root.selectedDisplay; bar: root.bar }
            WallpaperUi.WallpaperTab { visible: root.selectedTab === Tabs.index("wallpaper"); width: parent.width; tokens: panelTokens; dismiss: function() { root.close() }; controller: root.service ? root.service.wallpaper : null }
            Keys.KeybindingsTab { active: root.opened && visible; visible: root.selectedTab === Tabs.index("keybindings"); width: parent.width; tokens: panelTokens; service: root.service ? keybindingsTabPort : null }
            PanelUi.SettingsTab { visible: root.selectedTab === Tabs.index("settings"); width: parent.width; tokens: panelTokens; service: root.service ? settingsTabPort : null; pluginVersion: root.pluginVersion }
          }
        }
        PanelUi.PreviewStrip {
          id: previewStrip
          objectName: "stationPreviewStrip"
          width: parent.width
          visible: !!root.service && root.service.state === "previewing"
            && root.selectedTab !== Tabs.index("displays")
          tokens: panelTokens
          service: displaysTabPort
        }
      }
    }
  }
}
