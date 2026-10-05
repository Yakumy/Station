import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell.Io
import qs.Ui as Ui
import qs.Commons
import "Model.js" as Model
import "Binds.js" as Binds
import "." as Station

Ui.Panel {
  id: root
  moduleName: "yakumy.station"
  manageIpc: false

  property var service: bar && bar.shell ? bar.shell.serviceFor("yakumy.station") : null
  property int selectedTab: 0
  property int stationNumber: service ? service.currentStation : 1
  property string selectedDisplayName: service && service.displayDraft.length ? service.displayDraft[0].name : ""
  property int brightness: 0
  property bool brightnessAvailable: false
  property int pendingBrightness: 0
  property bool brightnessQueued: false
  property string editingBindingId: ""
  property var editingModifiers: ({ SUPER: false, CTRL: false, ALT: false, SHIFT: false })
  property string editingKey: ""
  readonly property string pluginVersion: "2.0.0"

  // Station design tokens (docs/v2/DESIGN-SYSTEM.md). Component code reads
  // these; nothing below this block hardcodes a colour, radius or step.
  //
  // Station owns its radius scale because Style.cornerRadius mirrors Hyprland's
  // decoration:rounding, which is 0 on most setups and would leave every card,
  // segment and node perfectly square.
  readonly property real radiusSm: Style.space(4)
  readonly property real radiusMd: Style.space(6)
  readonly property real radiusLg: Style.space(10)

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

  // Text ramp. Alphas rather than Qt.darker so the steps stay ordered on light
  // themes too, where darkening would darken text instead of muting it.
  readonly property color textPrimary: Color.popups.text
  readonly property color textSecondary: Util.alpha(Color.popups.text, 0.75)
  readonly property color textDim: Util.alpha(Color.popups.text, 0.55)
  readonly property color textDisabled: Util.alpha(Color.popups.text, 0.35)

  // Surface ramp: foreground mixed toward the background, one step per state.
  readonly property color surfaceOne: Util.alpha(Color.popups.text, 0.06)
  readonly property color surfaceTwo: Util.alpha(Color.popups.text, 0.10)
  readonly property color surfaceThree: Util.alpha(Color.popups.text, 0.14)
  readonly property color accentMuted: Util.alpha(Color.accent, 0.16)
  readonly property color accentHover: Qt.lighter(Color.accent, 1.25)
  readonly property color hairline: Util.alpha(Color.popups.text, 0.12)
  readonly property real focusHalo: Style.space(3)

  readonly property real disabledOpacity: 0.6
  readonly property real tabUnderline: Style.space(2)
  readonly property real controlHeight: Style.spacing.controlHeight

  component StationMark: Item {
    id: stationMark
    property color tint: Color.popups.text
    implicitWidth: Style.space(22)
    implicitHeight: Style.space(22)

    Image {
      id: markImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      source: Qt.resolvedUrl("../assets/station.svg")
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      visible: false
      layer.enabled: true
    }
    MultiEffect {
      anchors.fill: markImage
      source: markImage
      colorization: 1.0
      colorizationColor: stationMark.tint
    }
  }

  component ToolbarDropdown: Item {
    id: toolbarDropdown
    property string value: ""
    property var options: []
    signal changed(string value)
    implicitWidth: choiceLabel.implicitWidth + choiceChevron.implicitWidth + root.space2
    implicitHeight: root.controlHeight

    function labelFor(option) {
      return option && typeof option === "object" ? String(option.label) : String(option)
    }
    function valueFor(option) {
      return option && typeof option === "object" ? String(option.value) : String(option)
    }
    function currentLabel() {
      for (var i = 0; i < options.length; i++) if (valueFor(options[i]) === value) return labelFor(options[i])
      return options.length ? labelFor(options[0]) : ""
    }

    Text {
      id: choiceLabel
      anchors.left: parent.left
      anchors.right: choiceChevron.left
      anchors.verticalCenter: parent.verticalCenter
      text: toolbarDropdown.currentLabel()
      color: root.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    Text {
      id: choiceChevron
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "󰅀"
      color: root.textDim
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: choicePopup.open()
    }
    Popup {
      id: choicePopup
      y: toolbarDropdown.height + root.space1
      width: toolbarDropdown.width
      padding: root.space1
      background: Ui.BorderSurface {
        color: root.surfaceOne
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
        radius: root.radiusLg
      }
      contentItem: Column {
        width: choicePopup.availableWidth
        Repeater {
          model: toolbarDropdown.options
          delegate: Item {
            required property var modelData
            width: parent.width
            height: root.controlHeight
            readonly property bool current: toolbarDropdown.valueFor(modelData) === toolbarDropdown.value
            Ui.BorderSurface {
              anchors.fill: parent
              visible: current
              radius: root.radiusSm
              color: Color.menu.selectedBackground
              borderSpec: Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, Style.normalBorderWidth)
            }
            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: root.space2
              anchors.rightMargin: root.space2
              anchors.verticalCenter: parent.verticalCenter
              text: toolbarDropdown.labelFor(modelData)
              color: current ? Color.menu.selectedText : root.textPrimary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                toolbarDropdown.changed(toolbarDropdown.valueFor(modelData))
                choicePopup.close()
              }
            }
          }
        }
      }
    }
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
    var options = [{ value: "extend", label: "Mode: Extend" }, { value: "mirror", label: "Mode: Mirror" }]
    if (!service) return options
    service.displayDraft.forEach(function(display) {
      options.push({ value: "single:" + display.name,
        label: "Single · " + display.name + " · " + root.roleName(display) })
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
    selectedDisplayName = name
    refreshBrightness()
  }

  function changeMode(value) {
    if (!service || service.state !== "idle") return
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

  function refreshBrightness() {
    if (!selectedDisplayName || brightnessRead.running) return
    brightnessRead.command = ["omarchy-brightness-display", "--monitor", selectedDisplayName]
    brightnessRead.running = true
  }

  function queueBrightness(value) {
    brightnessDebounce.pending = Math.round(value)
    brightnessDebounce.restart()
  }

  function setBrightness(value) {
    if (!brightnessAvailable || !selectedDisplayName) return
    pendingBrightness = Math.max(1, Math.min(100, Math.round(value)))
    brightness = pendingBrightness
    if (brightnessWrite.running) { brightnessQueued = true; return }
    brightnessQueued = false
    brightnessWrite.command = ["omarchy", "brightness", "display", "--no-osd", "--monitor",
      selectedDisplayName, pendingBrightness + "%"]
    brightnessWrite.running = true
  }

  onOpenedChanged: if (opened) refreshBrightness()

  Process {
    id: brightnessRead
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: brightnessRead.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: {
      var first = captured.split("\n")[0].trim()
      root.brightnessAvailable = first !== "" && first !== "unavailable" && isFinite(Number(first))
      root.brightness = root.brightnessAvailable ? Number(first) : 0
    }
  }

  Timer {
    id: brightnessDebounce
    property int pending: 0
    interval: 180
    onTriggered: root.setBrightness(pending)
  }

  Process {
    id: brightnessWrite
    stdout: StdioCollector { waitForEnd: true }
    onExited: if (root.brightnessQueued) root.setBrightness(root.pendingBrightness)
  }

  readonly property color barFg: bar ? bar.barForeground : Color.bar.text
  // The Omarchy menu mark is an icon-font glyph whose ink box is exactly one
  // `Style.font.body` em, so deriving from the same token keeps this mark
  // pixel-matched to it at any theme font size.
  readonly property real stationLogoSize: Style.font.body
  readonly property real barControlMargin: Style.spaceReal(7.5)

  implicitWidth: barRow.implicitWidth
  implicitHeight: barRow.implicitHeight

  // Popout coordinator identity stays off the bar slot root so the host's
  // open-panel dot does not center across logo + [S n]. The underline under
  // the logo is drawn by the logo button itself.
  QtObject {
    id: popoutOwner
    property var panel: root
    readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing : false
    function close() { if (panel) panel.close() }
    function closeForPopoutSwitch() { if (panel) panel.closeForPopoutSwitch() }
  }

  Row {
    id: barRow
    spacing: 0

    Ui.WidgetButton {
      id: logoButton
      bar: root.bar
      text: "Station"
      tooltipText: "Station"
      labelVisible: false
      hasVisualContent: true
      horizontalMargin: 7.5
      fixedWidth: Math.round(root.stationLogoSize + root.barControlMargin * 2)
      fixedHeight: bar ? bar.barSize : Style.bar.sizeHorizontal
      onPressed: root.toggle()
      StationMark {
        anchors.centerIn: parent
        width: root.stationLogoSize
        height: root.stationLogoSize
        tint: root.barFg
      }
      Rectangle {
        visible: root.opened
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(1, Style.space(2))
        color: Color.accent
        radius: height / 2
      }
    }

    Ui.WidgetButton {
      id: stationButton
      bar: root.bar
      text: "[S" + root.stationNumber + "]"
      tooltipText: "Station"
      horizontalMargin: 7.5
      fontSize: Style.font.body
      onPressed: root.toggle()
    }
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: logoButton
    owner: popoutOwner
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: 0
    contentWidth: panel.fittedContentWidth(Style.space(748))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.selectedTab = (root.selectedTab + (direction > 0 ? 1 : 2)) % 3
      }

      Column {
        id: content
        x: 0
        width: parent.width
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(56)
          StationMark {
            id: logo
            width: Style.space(28)
            height: Style.space(28)
            tint: root.bar ? root.bar.foreground : Color.bar.text
            anchors.left: parent.left
            anchors.leftMargin: root.regionPadH
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            anchors.left: logo.right
            anchors.leftMargin: root.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.space1
            Text {
              text: "Station"
              color: root.textPrimary
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
            }
            Text {
              text: "v" + root.pluginVersion
              color: root.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.weight: Font.Medium
              font.letterSpacing: root.space1
            }
          }
        }

        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

        Item {
          id: toolbar
          width: parent.width
          height: root.controlHeight + root.space1
          Row {
            id: tabs
            anchors.left: parent.left
            anchors.leftMargin: root.regionPadH
            anchors.bottom: parent.bottom
            height: parent.height
            Repeater {
              model: ["Displays", "Keybindings", "Settings"]
              delegate: Item {
                id: tab
                required property int index
                required property string modelData
                readonly property bool conflicted: index === 1 && root.conflictCount > 0
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
                  // label only steps between text-2 and text-1.
                  color: tab.conflicted ? Color.urgent
                    : (root.selectedTab === tab.index ? root.textPrimary : root.textSecondary)
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
                  radius: root.radiusSm
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
            anchors.right: parent.right
            anchors.rightMargin: root.regionPadH
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.space2
            ToolbarDropdown {
              width: implicitWidth
              value: root.modeValue
              options: root.modeOptions
              onChanged: function(value) { root.changeMode(value) }
            }
            ToolbarDropdown {
              width: implicitWidth
              value: root.service ? root.service.config.direction : "ltr"
              options: [{ value: "ltr", label: "Direction: LTR" }, { value: "rtl", label: "Direction: RTL" }]
              onChanged: function(value) { if (root.service) root.service.setDirectionValue(value) }
            }
          }
        }

        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }
        Station.DisplaysTab { visible: root.selectedTab === 0; width: parent.width; panelRoot: root }
        Station.KeybindingsTab { visible: root.selectedTab === 1; width: parent.width; panelRoot: root }
        Station.SettingsTab { visible: root.selectedTab === 2; width: parent.width; panelRoot: root }
      }
    }
  }
}
