import QtQuick
import qs.Ui as Ui
import qs.Commons
import "Model.js" as Model
import "." as Displays
import "../panel" as PanelUi

Column {
  id: displayTab
  required property var tokens
  required property string selectedDisplayName
  required property var bar
  required property var selectDisplay
  required property var controls
  required property var service
  required property var selectedDisplay
  property string modeValue: "extend"
  property var modeOptions: []
  property var changeMode: function(value) {}
  readonly property real pad: tokens.regionPadH
  readonly property real gutter: tokens.space2
  readonly property var resolutionOptions: {
    var modes = selectedDisplay ? Model.resolutionChoices(selectedDisplay.availableModes) : []
    return modes.slice().sort(function(a, b) {
      var left = a.value.split("x").map(Number), right = b.value.split("x").map(Number)
      return left[0] * left[1] - right[0] * right[1] || left[0] - right[0]
    })
  }
  readonly property var refreshOptions: {
    if (!selectedDisplay) return []
    var mode = Model.parseMode(selectedDisplay.mode)
    if (!mode) return []
    return Model.refreshChoices(selectedDisplay.availableModes, mode.width + "x" + mode.height)
      .slice().sort(function(a, b) {
        return Model.parseMode(a.value).refresh - Model.parseMode(b.value).refresh
      })
  }
  readonly property var scaleOptions: [1, 1.25, 1.6, 2, 3, 4]

  function unavailableMessage(supported) {
    if (!selectedDisplay) return "Select a monitor."
    if (!selectedDisplay.enabled) return "Turn on this monitor."
    return supported ? "" : "Not available for this monitor."
  }

  component ControlMessage: Text {
    anchors.left: parent.left
    anchors.leftMargin: displayTab.gutter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: displayTab.tokens.space1
    width: parent.width - displayTab.gutter * 2
    visible: text !== ""
    horizontalAlignment: Text.AlignLeft
    wrapMode: Text.NoWrap
    elide: Text.ElideRight
    color: displayTab.tokens.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  component ControlLabel: PanelUi.ControlLabel {}

  function choiceIndex(options, value) {
    for (var i = 0; i < options.length; i++)
      if (String(options[i].value) === String(value)) return i
    return 0
  }

  function applyDisplayValue(key, value) {
    if (!service || !selectedDisplay || service.state !== "idle") return
    if (selectedDisplay[key] === value) return
    service.applyDisplaySetting(selectedDisplay.name, key, value)
  }

  spacing: 0

  Row {
    id: displayColumns
    width: parent.width
    height: Style.space(428)

    Column {
      id: leftColumn
      width: parent.width * 0.576
      spacing: 0

      Item {
        width: parent.width
        height: Style.space(28)
        Ui.PanelSectionHeader {
          anchors.left: parent.left
          anchors.leftMargin: displayTab.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "LAYOUT"
          foreground: displayTab.tokens.textPrimary
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: displayTab.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "DRAG TO ARRANGE"
          color: displayTab.tokens.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Displays.DisplayLayout {
        id: layoutCanvas
        width: parent.width - displayTab.pad * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        service: displayTab.service
        tokens: displayTab.tokens
        selectedDisplayName: displayTab.selectedDisplayName
        onDisplaySelected: function(name) { displayTab.selectDisplay(name) }
        PanelUi.InlineDropdown {
          objectName: "displayModeDropdown"
          anchors.top: parent.top; anchors.topMargin: displayTab.tokens.space2
          anchors.right: parent.right; anchors.rightMargin: displayTab.tokens.space3
          z: 10
          prefix: "Mode: "
          value: displayTab.modeValue
          options: displayTab.modeOptions
          popupMinWidth: displayTab.tokens.space6 * 7
          popupAlignRight: true
          foreground: displayTab.tokens.textDim
          onChanged: function(value) { displayTab.changeMode(value) }
        }
      }

      Text {
        visible: displayTab.service && displayTab.service.layoutError !== ""
        width: parent.width - displayTab.pad * 2
        x: displayTab.pad
        topPadding: displayTab.gutter
        text: displayTab.service ? displayTab.service.layoutError : ""
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Rectangle {
      width: Math.max(1, Style.normalBorderWidth)
      height: displayColumns.height
      color: Color.popups.text
      opacity: 0.12
    }

    Column {
      id: rightColumn
      width: parent.width - leftColumn.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      readonly property real sideInset: Style.space(28)

      Item {
        width: parent.width
        height: Style.space(28)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: rightColumn.sideInset
          anchors.verticalCenter: parent.verticalCenter
          text: displayTab.selectedDisplay ? "Selected: " + displayTab.selectedDisplay.name : "No display selected"
          color: displayTab.tokens.textPrimary
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelUi.ControlFrame {
        id: controlFrame
        height: Style.space(370)

        Column {
          anchors.fill: parent
          spacing: 0

          Item {
            width: parent.width
            height: controlFrame.height / 5
            ControlLabel {
              text: "BRIGHTNESS"
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: displayTab.gutter
              anchors.top: parent.top
              anchors.topMargin: displayTab.gutter
              text: displayTab.controls.brightnessAvailable ? displayTab.controls.brightness + "%" : "—"
              color: displayTab.tokens.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: displayTab.bar
              minimum: 1
              maximum: 100
              integer: true
              value: displayTab.controls.brightness
              enabled: displayTab.controls.brightnessAvailable
                && displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
              opacity: enabled ? 1 : displayTab.tokens.disabledOpacity
              onMoved: function(value) { displayTab.controls.brightness = Math.round(value) }
              onReleased: function(value) { displayTab.controls.queueBrightness(value) }
            }
            ControlMessage {
              text: displayTab.controls.brightnessLoading ? ""
                : displayTab.unavailableMessage(displayTab.controls.brightnessAvailable)
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: displayTab.tokens.textPrimary }
          }

          Item {
            width: parent.width
            height: controlFrame.height / 5
            ControlLabel {
              text: "TEXT SIZE (ALL DISPLAYS)"
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: displayTab.gutter
              anchors.top: parent.top
              anchors.topMargin: displayTab.gutter
              text: displayTab.controls.displayedTextSize() + "px"
              color: displayTab.tokens.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: displayTab.bar
              minimum: 0
              maximum: displayTab.controls.textSizeStops.length - 1
              step: 1
              integer: true
              tickCount: displayTab.controls.textSizeStops.length
              value: displayTab.controls.currentTextIndex()
              enabled: displayTab.controls.textSizeStops.length > 1
              opacity: enabled ? 1 : displayTab.tokens.disabledOpacity
              onReleased: function(value) { displayTab.controls.setTextSizeIndex(Math.round(value)) }
            }
            ControlMessage {
              text: displayTab.controls.textSizeStops.length > 1 ? "" : "Not available."
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: displayTab.tokens.textPrimary }
          }

          Item {
            width: parent.width
            height: controlFrame.height / 5
            ControlLabel {
              text: "SCALE"
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: displayTab.gutter
              anchors.top: parent.top
              anchors.topMargin: displayTab.gutter
              text: displayTab.selectedDisplay ? displayTab.selectedDisplay.scale + "x" : "—"
              color: displayTab.tokens.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: displayTab.bar
              minimum: 0
              maximum: displayTab.scaleOptions.length - 1
              step: 1
              integer: true
              tickCount: displayTab.scaleOptions.length
              value: displayTab.selectedDisplay
                ? Math.max(0, displayTab.scaleOptions.indexOf(Number(displayTab.selectedDisplay.scale))) : 0
              enabled: displayTab.service && displayTab.service.state === "idle"
                && displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
                && displayTab.scaleOptions.length > 1
              opacity: enabled ? 1 : displayTab.tokens.disabledOpacity
              onReleased: function(value) {
                displayTab.applyDisplayValue("scale", displayTab.scaleOptions[Math.round(value)])
              }
            }
            ControlMessage {
              text: displayTab.unavailableMessage(displayTab.scaleOptions.length > 1)
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: displayTab.tokens.textPrimary }
          }

          Item {
            width: parent.width
            height: controlFrame.height / 5
            ControlLabel {
              text: "RESOLUTION"
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: displayTab.gutter
              anchors.top: parent.top
              anchors.topMargin: displayTab.gutter
              text: {
                var mode = displayTab.selectedDisplay ? Model.parseMode(displayTab.selectedDisplay.mode) : null
                return mode ? mode.width + "x" + mode.height : "—"
              }
              color: displayTab.tokens.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: displayTab.bar
              minimum: 0
              maximum: Math.max(0, displayTab.resolutionOptions.length - 1)
              step: 1
              integer: true
              tickCount: displayTab.resolutionOptions.length
              value: {
                var mode = displayTab.selectedDisplay ? Model.parseMode(displayTab.selectedDisplay.mode) : null
                return mode ? displayTab.choiceIndex(displayTab.resolutionOptions, mode.width + "x" + mode.height) : 0
              }
              enabled: displayTab.service && displayTab.service.state === "idle"
                && displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
                && displayTab.resolutionOptions.length > 1
              opacity: enabled ? 1 : displayTab.tokens.disabledOpacity
              onReleased: function(value) {
                var choice = displayTab.resolutionOptions[Math.round(value)]
                if (!choice || !displayTab.selectedDisplay) return
                var exact = Model.modeForResolution(displayTab.selectedDisplay.availableModes,
                  choice.value, displayTab.selectedDisplay.mode)
                displayTab.applyDisplayValue("mode", exact)
              }
            }
            ControlMessage {
              text: displayTab.unavailableMessage(displayTab.resolutionOptions.length > 1)
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: displayTab.tokens.textPrimary }
          }

          Item {
            width: parent.width
            height: controlFrame.height / 5
            ControlLabel {
              text: "REFRESH RATE"
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: displayTab.gutter
              anchors.top: parent.top
              anchors.topMargin: displayTab.gutter
              text: {
                var mode = displayTab.selectedDisplay ? Model.parseMode(displayTab.selectedDisplay.mode) : null
                return mode ? mode.refresh + " Hz" : "—"
              }
              color: displayTab.tokens.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: displayTab.bar
              minimum: 0
              maximum: Math.max(0, displayTab.refreshOptions.length - 1)
              step: 1
              integer: true
              tickCount: displayTab.refreshOptions.length
              value: displayTab.selectedDisplay
                ? displayTab.choiceIndex(displayTab.refreshOptions, displayTab.selectedDisplay.mode) : 0
              enabled: displayTab.service && displayTab.service.state === "idle"
                && displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
                && displayTab.refreshOptions.length > 1
              opacity: enabled ? 1 : displayTab.tokens.disabledOpacity
              onReleased: function(value) {
                var choice = displayTab.refreshOptions[Math.round(value)]
                if (choice) displayTab.applyDisplayValue("mode", choice.value)
              }
            }
            ControlMessage {
              text: displayTab.unavailableMessage(displayTab.refreshOptions.length > 1)
            }
          }
        }
      }
    }
  }

  Item {
    width: parent.width
    height: Style.space(66)
    readonly property bool previewing: displayTab.service && displayTab.service.state === "previewing"
    Ui.PanelSeparator { width: parent.width; foreground: displayTab.tokens.textPrimary }
    Text {
      visible: parent.previewing
      anchors.left: parent.left
      anchors.leftMargin: displayTab.pad
      anchors.right: revertButton.left
      anchors.rightMargin: displayTab.gutter
      anchors.verticalCenter: parent.verticalCenter
      text: displayTab.service && displayTab.service.previewBusy ? "Applying layout and moving windows…" : "Keep these settings? Reverting in "
        + (displayTab.service ? displayTab.service.previewSeconds : 0) + " s"
      color: displayTab.tokens.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    PanelUi.ActionButton {
      id: keepButton
      visible: parent.previewing
      anchors.right: parent.right
      anchors.rightMargin: displayTab.pad
      anchors.verticalCenter: parent.verticalCenter
      text: "Keep"
      enabled: displayTab.service && !displayTab.service.previewBusy
      accent: Color.accent
      background: Color.accent
      foreground: Color.popups.background
      onClicked: displayTab.service.keepPreview()
    }
    PanelUi.ActionButton {
      id: revertButton
      visible: parent.previewing
      anchors.right: keepButton.left
      anchors.rightMargin: displayTab.gutter
      anchors.verticalCenter: parent.verticalCenter
      text: "Revert"
      enabled: displayTab.service && !displayTab.service.previewBusy
      bordered: true
      foreground: Color.popups.text
      onClicked: displayTab.service.revertPreview("")
    }
  }
}
