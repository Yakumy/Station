import QtQuick
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
  property string themeName: "THEME"

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

  onOpenedChanged: if (opened) { refreshBrightness(); themeProbe.running = true }

  Process {
    id: themeProbe
    command: ["readlink", "-f", Color.currentThemePath]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: themeProbe.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: {
      var parts = captured.trim().split("/")
      root.themeName = String(parts[parts.length - 1] || "THEME").replace(/[-_]/g, " ").toUpperCase()
    }
  }

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

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  Ui.WidgetButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: "▯▮▯  [S " + root.stationNumber + "]"
    tooltipText: "Station"
    fontSize: Style.font.body
    onPressed: root.toggle()
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(748))
    contentHeight: panel.cappedContentHeight(panel.fittedContentHeight(content.implicitHeight) * 1.1)

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.selectedTab = (root.selectedTab + (direction > 0 ? 1 : 2)) % 3
      }

      Column {
        id: content
        width: parent.width
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(56)
          Text {
            id: logo
            textFormat: Text.PlainText
            text: "▯▮▯"
            color: root.bar ? root.bar.foreground : Color.bar.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            anchors.left: logo.right
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs
            Text {
              text: "Station"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.themeName
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: Style.space(1)
            }
          }
        }

        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

        Item {
          id: toolbar
          width: parent.width
          height: Style.space(40)
          Row {
            id: tabs
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: parent.height
            Repeater {
              model: ["Displays", "Keybindings", "Settings"]
              delegate: Item {
                id: tab
                required property int index
                required property string modelData
                height: tabs.height
                width: tabLabel.implicitWidth + Style.spacing.lg * 2
                  + (index === 1 && root.conflictCount ? badge.width + Style.spacing.xs : 0)
                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  anchors.horizontalCenterOffset: tab.index === 1 && root.conflictCount
                    ? -(badge.width + Style.spacing.xs) / 2 : 0
                  text: tab.modelData
                  color: tab.index === 1 && root.conflictCount ? Color.urgent
                    : (root.selectedTab === tab.index ? Color.accent : Qt.darker(Color.popups.text, 1.35))
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Rectangle {
                  id: badge
                  visible: tab.index === 1 && root.conflictCount > 0
                  anchors.left: tabLabel.right
                  anchors.leftMargin: Style.spacing.xs
                  anchors.verticalCenter: tabLabel.verticalCenter
                  width: Math.max(Style.space(16), badgeText.implicitWidth + Style.spacing.xs * 2)
                  height: Style.space(16)
                  color: Color.urgent
                  radius: Style.cornerRadius
                  Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.conflictCount
                    color: Color.popups.background
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.max(1, Style.normalBorderWidth)
                  color: tab.index === 1 && root.conflictCount ? Color.urgent : Color.accent
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
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs
            Ui.Dropdown {
              width: Style.space(142)
              showLabel: false
              value: root.modeValue
              options: root.modeOptions
              foreground: Color.popups.text
              onChanged: function(value) { root.changeMode(value) }
            }
            Ui.Dropdown {
              width: Style.space(132)
              showLabel: false
              value: root.service ? root.service.config.direction : "ltr"
              options: [{ value: "ltr", label: "Direction: LTR" }, { value: "rtl", label: "Direction: RTL" }]
              foreground: Color.popups.text
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
