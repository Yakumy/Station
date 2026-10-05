import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Ui as Ui
import qs.Commons
import "lib/Model.js" as Model
import "lib/Binds.js" as Binds

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
  property string themeName: "THEME"
  readonly property int conflictCount: service ? service.bindStatuses.filter(function(item) { return item.status === "conflict" }).length : 0

  readonly property var selectedDisplay: {
    if (!service) return null
    for (var i = 0; i < service.displayDraft.length; i++)
      if (service.displayDraft[i].name === selectedDisplayName) return service.displayDraft[i]
    return service.displayDraft.length ? service.displayDraft[0] : null
  }

  function selectDisplay(name) {
    selectedDisplayName = name
    refreshBrightness()
  }

  function refreshBrightness() {
    if (!selectedDisplayName || brightnessRead.running) return
    brightnessRead.command = ["omarchy-brightness-display", "--monitor", selectedDisplayName]
    brightnessRead.running = true
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
    contentWidth: panel.fittedContentWidth(Style.space(680))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: content.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: content
          width: scrollArea.availableWidth
          spacing: Style.spacing.md

        Item {
          width: parent.width
          implicitHeight: Math.max(logo.implicitHeight, titles.implicitHeight)

          Text {
            id: logo
            textFormat: Text.PlainText
            text: "▯▮▯"
            color: root.bar ? root.bar.foreground : Color.bar.text
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: titles
            anchors.left: logo.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: parent.right
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

        Row {
          width: parent.width
          spacing: Style.spacing.sm
          Repeater {
            model: ["Displays", "Keybindings" + (root.conflictCount ? "  " + root.conflictCount : ""), "Settings"]
            delegate: Ui.Button {
              required property int index
              required property string modelData
              text: modelData
              selected: root.selectedTab === index
              foreground: index === 1 && root.service && root.service.bindStatuses.some(function(item) { return item.status === "conflict" })
                ? Color.urgent : Color.popups.text
              accent: index === 1 ? Color.urgent : Color.accent
              onClicked: root.selectedTab = index
            }
          }
        }

        Row {
          visible: root.selectedTab === 0
          width: parent.width
          spacing: Style.spacing.sm
          Ui.Button {
            text: "Extend"
            selected: root.service && root.service.draftMode === "extend"
            foreground: Color.popups.text
            onClicked: if (root.service && root.service.state === "idle") root.service.setModeValue("extend", "")
          }
          Ui.Button {
            text: "Mirror"
            selected: root.service && root.service.draftMode === "mirror"
            foreground: Color.popups.text
            onClicked: if (root.service && root.service.state === "idle") root.service.setModeValue("mirror", "")
          }
          Ui.Button {
            text: "Single · " + (root.selectedDisplay ? root.selectedDisplay.name : "display")
            selected: root.service && root.service.draftMode === "single"
            foreground: Color.popups.text
            onClicked: if (root.service && root.selectedDisplay && root.service.state === "idle")
              root.service.setModeValue("single", root.selectedDisplay.name)
          }
          Item { width: Style.spacing.md; height: Style.spacing.md }
          Ui.Button {
            text: "LTR"
            selected: root.service && root.service.config.direction === "ltr"
            foreground: Color.popups.text
            onClicked: if (root.service) root.service.setDirectionValue("ltr")
          }
          Ui.Button {
            text: "RTL"
            selected: root.service && root.service.config.direction === "rtl"
            foreground: Color.popups.text
            onClicked: if (root.service) root.service.setDirectionValue("rtl")
          }
        }

        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

        Column {
          visible: root.selectedTab === 0
          width: parent.width
          spacing: Style.spacing.sm

          Ui.PanelSectionHeader { text: "LAYOUT · LOGICAL COORDINATES · DRAG TO ARRANGE"; foreground: Color.popups.text; fontFamily: Style.font.family }
          Ui.BorderSurface {
            id: canvas
            width: parent.width
            height: Style.space(190)
            color: Color.popups.background
            borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
            radius: Style.cornerRadius
            readonly property real zoom: 0.09
            readonly property real inset: Style.spacing.md
            function minimum(axis) {
              var value = 0
              if (!root.service || !root.service.displayDraft.length) return value
              value = Number(root.service.displayDraft[0][axis]) || 0
              for (var i = 1; i < root.service.displayDraft.length; i++)
                value = Math.min(value, Number(root.service.displayDraft[i][axis]) || 0)
              return value
            }
            Repeater {
              model: root.service ? root.service.displayDraft : []
              delegate: Ui.BorderSurface {
                id: monitorCard
                required property var modelData
                readonly property bool rotated: [1, 3, 5, 7].indexOf(Number(modelData.transform)) !== -1
                readonly property real logicalWidth: (rotated ? Number(modelData.height) : Number(modelData.width)) / Number(modelData.scale)
                readonly property real logicalHeight: (rotated ? Number(modelData.width) : Number(modelData.height)) / Number(modelData.scale)
                x: canvas.inset + (Number(modelData.x) - canvas.minimum("x")) * canvas.zoom
                y: canvas.inset + (Number(modelData.y) - canvas.minimum("y")) * canvas.zoom
                width: Math.max(Style.space(70), logicalWidth * canvas.zoom)
                height: Math.max(Style.space(42), logicalHeight * canvas.zoom)
                color: root.selectedDisplayName === modelData.name ? Color.menu.selectedBackground : Color.menu.background
                borderSpec: Border.controlSpec(root.selectedDisplayName === modelData.name ? "selected" : "normal", Color.menu.text, Color.accent)
                radius: Style.cornerRadius
                opacity: modelData.enabled ? 1 : 0.5
                Text {
                  anchors.centerIn: parent
                  text: modelData.name + "\nLane " + modelData.lane
                  horizontalAlignment: Text.AlignHCenter
                  color: root.selectedDisplayName === modelData.name ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  drag.target: monitorCard
                  cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  onPressed: root.selectDisplay(modelData.name)
                  onReleased: {
                    if (!root.service || root.service.state !== "idle") return
                    var nx = (monitorCard.x - canvas.inset) / canvas.zoom + canvas.minimum("x")
                    var ny = (monitorCard.y - canvas.inset) / canvas.zoom + canvas.minimum("y")
                    var snapped = Model.snapPosition(modelData, nx, ny, root.service.displayDraft)
                    root.service.setDisplayValue(modelData.name, "x", snapped.x)
                    root.service.setDisplayValue(modelData.name, "y", snapped.y)
                    root.service.previewLayout()
                  }
                }
              }
            }
          }

          Ui.PanelSectionHeader { text: "DISPLAYS"; foreground: Color.popups.text; fontFamily: Style.font.family }
          Text {
            visible: root.service && root.service.unmanaged.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Station manages three displays. Mirror or disable: " + (root.service ? root.service.unmanaged.join(", ") : "")
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Repeater {
            model: root.service ? root.service.displayDraft : []
            delegate: Ui.BorderSurface {
              required property var modelData
              width: content.width
              implicitHeight: displayRow.implicitHeight + Style.spacing.md
              color: Color.menu.background
              borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Style.normalBorderWidth)
              radius: Style.cornerRadius
              MouseArea { anchors.fill: parent; onClicked: root.selectDisplay(modelData.name) }
              Row {
                id: displayRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.spacing.sm
                spacing: Style.spacing.sm
                Text {
                  text: modelData.name + " · " + (modelData.enabled ? "Lane " + modelData.lane : "Off")
                  color: Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: Math.max(Style.space(160), displayRow.width - Style.space(250))
                  text: modelData.description
                  elide: Text.ElideRight
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Ui.Button {
                  text: modelData.enabled ? "✓" : "Enable"
                  selected: modelData.enabled
                  foreground: Color.menu.text
                  onClicked: {
                    if (!root.service || root.service.state !== "idle") return
                    var enabledCount = root.service.displayDraft.filter(function(display) { return display.enabled }).length
                    if (modelData.enabled && enabledCount <= 1) return
                    root.service.setDisplayValue(modelData.name, "enabled", !modelData.enabled)
                    root.service.previewLayout()
                  }
                }
              }
            }
          }

          Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

          Column {
            visible: root.selectedDisplay !== null
            width: parent.width
            spacing: Style.spacing.sm
            Row {
              width: parent.width
              Ui.PanelSectionHeader { text: "BRIGHTNESS"; foreground: Color.popups.text; fontFamily: Style.font.family }
              Item { width: parent.width - Style.space(130); height: Style.spacing.md }
              Text { text: root.brightnessAvailable ? root.brightness + "%" : "UNAVAILABLE"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            }
            Ui.PanelSlider {
              width: parent.width
              bar: root.bar
              minimum: 1
              maximum: 100
              integer: true
              value: root.brightness
              enabled: root.brightnessAvailable && root.selectedDisplay && root.selectedDisplay.enabled
              opacity: enabled ? 1 : 0.4
              onMoved: function(value) { root.brightness = Math.round(value) }
              onReleased: function(value) { brightnessDebounce.pending = Math.round(value); brightnessDebounce.restart() }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md
              Ui.Dropdown {
                width: (parent.width - Style.spacing.md * 2) / 3
                label: "RESOLUTION"
                value: root.selectedDisplay && Model.parseMode(root.selectedDisplay.mode)
                  ? Model.parseMode(root.selectedDisplay.mode).width + "x" + Model.parseMode(root.selectedDisplay.mode).height : ""
                options: root.selectedDisplay ? Model.resolutionChoices(root.selectedDisplay.availableModes) : []
                onChanged: function(value) {
                  if (!root.service || !root.selectedDisplay || root.service.state !== "idle") return
                  var exact = Model.modeForResolution(root.selectedDisplay.availableModes, value, root.selectedDisplay.mode)
                  root.service.setDisplayValue(root.selectedDisplay.name, "mode", exact)
                  root.service.previewLayout()
                }
              }
              Ui.Dropdown {
                width: (parent.width - Style.spacing.md * 2) / 3
                label: "REFRESH"
                value: root.selectedDisplay ? root.selectedDisplay.mode : ""
                options: root.selectedDisplay && Model.parseMode(root.selectedDisplay.mode)
                  ? Model.refreshChoices(root.selectedDisplay.availableModes,
                    Model.parseMode(root.selectedDisplay.mode).width + "x" + Model.parseMode(root.selectedDisplay.mode).height) : []
                onChanged: function(value) {
                  if (!root.service || !root.selectedDisplay || root.service.state !== "idle") return
                  root.service.setDisplayValue(root.selectedDisplay.name, "mode", value)
                  root.service.previewLayout()
                }
              }
              Ui.Dropdown {
                width: (parent.width - Style.spacing.md * 2) / 3
                label: "ROTATION"
                value: root.selectedDisplay ? String(root.selectedDisplay.transform) : "0"
                options: [{ value: "0", label: "Normal" }, { value: "1", label: "90°" },
                  { value: "2", label: "180°" }, { value: "3", label: "270°" }]
                onChanged: function(value) {
                  if (!root.service || !root.selectedDisplay || root.service.state !== "idle") return
                  root.service.setDisplayValue(root.selectedDisplay.name, "transform", Number(value))
                  root.service.previewLayout()
                }
              }
            }

            Ui.PanelSectionHeader { text: "SCALE"; foreground: Color.popups.text; fontFamily: Style.font.family }
            Row {
              width: parent.width
              spacing: Style.spacing.xs
              Repeater {
                model: [1, 1.25, 1.6, 2, 3, 4]
                delegate: Ui.Button {
                  required property real modelData
                  text: modelData + "x"
                  selected: root.selectedDisplay && Number(root.selectedDisplay.scale) === modelData
                  foreground: Color.popups.text
                  onClicked: {
                    if (!root.service || !root.selectedDisplay || root.service.state !== "idle") return
                    root.service.setDisplayValue(root.selectedDisplay.name, "scale", modelData)
                    root.service.previewLayout()
                  }
                }
              }
            }

            Ui.PanelSectionHeader { text: "ROLE"; foreground: Color.popups.text; fontFamily: Style.font.family }
            Row {
              spacing: Style.spacing.xs
              Repeater {
                model: ["Primary", "Secondary", "Third"]
                delegate: Ui.Button {
                  required property int index
                  required property string modelData
                  visible: root.service && index < root.service.displayDraft.filter(function(display) { return display.enabled }).length
                  text: modelData
                  selected: root.selectedDisplay && root.service.roleOf(root.selectedDisplay.name) === index
                  foreground: Color.popups.text
                  onClicked: if (root.service && root.selectedDisplay && root.service.state === "idle")
                    root.service.swapRole(root.selectedDisplay.name, index)
                }
              }
            }
          }

          Text {
            visible: root.service && root.service.layoutError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.service ? root.service.layoutError : ""
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Row {
            visible: root.service && root.service.state === "previewing"
            width: parent.width
            spacing: Style.spacing.sm
            Text {
              width: parent.width - keepButton.width - revertButton.width - Style.spacing.sm * 2
              text: "Keep these settings? Reverting in " + (root.service ? root.service.previewSeconds : 0) + " s"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Ui.Button { id: revertButton; text: "Revert"; foreground: Color.popups.text; onClicked: root.service.revertPreview("") }
            Ui.Button { id: keepButton; text: "Keep"; selected: true; foreground: Color.popups.text; accent: Color.accent; onClicked: root.service.keepPreview() }
          }
        }

        Column {
          visible: root.selectedTab === 1
          width: parent.width
          spacing: Style.spacing.xs
          Ui.PanelSectionHeader { text: "KEYBINDINGS"; foreground: Color.popups.text; fontFamily: Style.font.family }
          Repeater {
            model: root.service ? root.service.bindStatuses : []
            delegate: Column {
              id: bindingRow
              required property var modelData
              width: content.width
              spacing: Style.spacing.sm
              property var editMods: ({ SUPER: false, CTRL: false, ALT: false, SHIFT: false })
              function startEditing() {
                var normalized = Binds.normalize(modelData.combo).split("+")
                editMods = { SUPER: normalized.indexOf("SUPER") !== -1,
                  CTRL: normalized.indexOf("CTRL") !== -1, ALT: normalized.indexOf("ALT") !== -1,
                  SHIFT: normalized.indexOf("SHIFT") !== -1 }
                keyInput.text = normalized[normalized.length - 1] || ""
                root.editingBindingId = modelData.id
              }
              function toggleModifier(name) {
                var next = Object.assign({}, editMods)
                next[name] = !next[name]
                editMods = next
              }
              function composedCombo() {
                var parts = []
                ;["SUPER", "CTRL", "ALT", "SHIFT"].forEach(function(mod) { if (editMods[mod]) parts.push(mod) })
                if (keyInput.text.trim()) parts.push(keyInput.text.trim())
                return parts.join(" + ")
              }
              Row {
                width: parent.width
                spacing: Style.spacing.sm
                Text { width: parent.width * 0.4; text: modelData.label; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
                Text { width: parent.width * 0.36; text: modelData.combo; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                Text { text: modelData.status.toUpperCase(); color: modelData.status === "conflict" ? Color.urgent : Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              }
              Text {
                visible: modelData.status === "conflict"
                width: parent.width
                text: "Used by " + modelData.owners.join(", ")
                wrapMode: Text.WordWrap
                color: Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Row {
                visible: modelData.status === "conflict"
                spacing: Style.spacing.sm
                Ui.Button { text: "Pick another key"; foreground: Color.popups.text; onClicked: bindingRow.startEditing() }
                Ui.Button { text: "Replace and unbind it"; selected: true; foreground: Color.popups.text; accent: Color.urgent; onClicked: root.service.approveBinding(modelData.combo) }
              }
              Row {
                visible: root.editingBindingId === modelData.id
                spacing: Style.spacing.xs
                Repeater {
                  model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                  delegate: Ui.Button {
                    required property string modelData
                    text: modelData
                    selected: bindingRow.editMods[modelData]
                    foreground: Color.popups.text
                    onClicked: bindingRow.toggleModifier(modelData)
                  }
                }
                Ui.TextField { id: keyInput; width: Style.space(90); placeholderText: "KEY"; foreground: Color.popups.text; onAccepted: applyBinding.clicked() }
                Ui.Button {
                  id: applyBinding
                  text: "Apply"
                  selected: true
                  foreground: Color.popups.text
                  onClicked: {
                    if (root.service.setBinding(modelData.id, bindingRow.composedCombo()) === "ok")
                      root.editingBindingId = ""
                  }
                }
              }
            }
          }
        }

        Column {
          visible: root.selectedTab === 2
          width: parent.width
          spacing: Style.spacing.sm
          Ui.PanelSectionHeader { text: "SETTINGS"; foreground: Color.popups.text; fontFamily: Style.font.family }
          Ui.Toggle {
            width: parent.width
            label: "Hide Omarchy's workspace indicator"
            description: "Station records its position and restores it when disabled or removed."
            checked: root.service && root.service.config.hideNative
            foreground: Color.popups.text
            onClicked: root.service.setSetting("hideNative", !checked)
          }
          Ui.Toggle {
            width: parent.width
            label: "Follow focus"
            description: "Keep managed displays on the same station."
            checked: root.service && root.service.config.followFocus
            foreground: Color.popups.text
            onClicked: root.service.setSetting("followFocus", !checked)
          }
          Row {
            width: parent.width
            spacing: Style.spacing.md
            Ui.Dropdown {
              width: (parent.width - Style.spacing.md) / 2
              label: "UNPLUG GRACE DELAY"
              value: root.service ? String(root.service.config.graceMs) : "5000"
              options: [{ value: "0", label: "No delay" }, { value: "3000", label: "3 seconds" },
                { value: "5000", label: "5 seconds" }, { value: "10000", label: "10 seconds" }]
              onChanged: function(value) { root.service.setSetting("graceMs", Number(value)) }
            }
            Ui.Dropdown {
              width: (parent.width - Style.spacing.md) / 2
              label: "MINIMUM STATIONS"
              value: root.service ? String(root.service.config.minStations) : "3"
              options: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
              onChanged: function(value) { root.service.setSetting("minStations", Number(value)) }
            }
          }
          Ui.Button {
            text: "Remove Station block from monitors.lua"
            foreground: Color.urgent
            bordered: true
            onClicked: if (root.service) root.service.removeStationBlock()
          }
          Text { text: "Installed version  2.0.0"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
        }
        }
      }
    }
  }
}
