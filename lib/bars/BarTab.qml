import QtQuick
import "../panel" as PanelUi
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "." as Bars

Column {
  id: root
  required property var tokens
  required property var bar
  required property var selectDisplay
  required property var service
  required property var selectedDisplay
  readonly property var selectedBar: selectedDisplay && service
    ? service.monitorBar(selectedDisplay.name)
    : ({ enabled: true, position: "top", width: 100, height: 0, background: "solid", style: "default", contentSize: 0 })
  readonly property int selectedMinimumWidth: selectedDisplay && service
    ? service.monitorBarMinimum(selectedDisplay.name) : 1
  readonly property int selectedMinimumHeight: selectedBar.position === "left" || selectedBar.position === "right"
    ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int selectedMaximumHeight: selectedDisplay && service
    ? Math.max(selectedMinimumHeight, service.monitorBarMaximumHeight(selectedDisplay.name))
    : selectedMinimumHeight
  readonly property int selectedHeight: Math.max(selectedMinimumHeight, Math.min(selectedMaximumHeight,
    Number(selectedBar.height) > 0 ? Number(selectedBar.height) : selectedMinimumHeight))
  readonly property int selectedMinimumContentSize: Math.max(1, Math.ceil(Style.font.body))
  readonly property int selectedRequestedContentSize: Number(selectedBar.contentSize) > 0
    ? Number(selectedBar.contentSize) : selectedMinimumContentSize
  readonly property int selectedMaximumContentSize: selectedDisplay && service
    ? Math.max(selectedMinimumContentSize, service.monitorBarMaximumContent(selectedDisplay.name))
    : selectedMinimumContentSize
  readonly property int selectedContentSize: Math.max(selectedMinimumContentSize,
    Math.min(selectedMaximumContentSize, selectedRequestedContentSize))
  readonly property real pad: tokens.regionPadH
  spacing: 0

  component Caption: Text {
    color: root.tokens.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Row {
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
          anchors.leftMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "LAYOUT"
          foreground: root.tokens.textPrimary
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "SELECT A SIDE"
          color: root.tokens.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Bars.BarLayout {
        id: layoutCanvas
        width: parent.width - root.pad * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        tokens: root.tokens; service: root.service
        selectedDisplayName: root.selectedDisplay ? root.selectedDisplay.name : ""
        onDisplaySelected: function(name) { root.selectDisplay(name) }
      }
    }

    Rectangle {
      width: Math.max(1, Style.normalBorderWidth)
      height: parent.height
      color: Commons.Color.popups.text
      opacity: 0.12
    }

    Column {
      width: parent.width - leftColumn.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Item {
        width: parent.width
        height: Style.space(28)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(56)
          text: root.selectedDisplay ? "Selected: " + root.selectedDisplay.name : "No monitor selected"
          color: root.tokens.textPrimary
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
            id: contentSizeRow
            width: parent.width
            height: controlFrame.height / 5
            PanelUi.ControlLabel { text: "CONTENT SIZE" }
            Caption {
              anchors.right: parent.right
              anchors.rightMargin: root.tokens.space2
              anchors.top: parent.top
              anchors.topMargin: root.tokens.space2
              text: root.selectedContentSize + " px"
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: root.bar
              minimum: root.selectedMinimumContentSize
              maximum: root.selectedMaximumContentSize
              integer: true
              value: root.selectedContentSize
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.tokens.disabledOpacity
              onReleased: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarContentSize(root.selectedDisplay.name, Math.round(value))
              }
            }
            Caption {
              visible: root.selectedRequestedContentSize > root.selectedMaximumContentSize
              anchors.left: parent.left
              anchors.leftMargin: root.tokens.space2
              anchors.bottom: parent.bottom
              anchors.bottomMargin: root.tokens.space1
              width: parent.width - root.tokens.space2 * 2
              text: "Maximum " + root.selectedMaximumContentSize + " px — content needs more bar space."
              color: Commons.Color.urgent
              elide: Text.ElideRight
            }
            Ui.PanelSeparator {
              anchors.bottom: parent.bottom
              width: parent.width
              foreground: Commons.Color.popups.text
            }
          }

          Item {
            id: heightRow
            width: parent.width
            height: controlFrame.height / 5
            PanelUi.ControlLabel { text: "HEIGHT" }
            Caption {
              anchors.right: parent.right
              anchors.rightMargin: root.tokens.space2
              anchors.top: parent.top
              anchors.topMargin: root.tokens.space2
              text: root.selectedHeight + " px"
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: root.bar
              minimum: root.selectedMinimumHeight
              maximum: root.selectedMaximumHeight
              integer: true
              value: root.selectedHeight
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.tokens.disabledOpacity
              onReleased: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarHeight(root.selectedDisplay.name, Math.round(value))
              }
            }
            Ui.PanelSeparator {
              anchors.bottom: parent.bottom
              width: parent.width
              foreground: Commons.Color.popups.text
            }
          }

          Item {
            id: widthRow
            width: parent.width
            height: controlFrame.height / 5
            PanelUi.ControlLabel { text: "WIDTH" }
            Caption {
              anchors.right: parent.right
              anchors.rightMargin: root.tokens.space2
              anchors.top: parent.top
              anchors.topMargin: root.tokens.space2
              text: root.selectedBar.width + "%"
            }
            PanelUi.ControlSlider {
              anchors.centerIn: parent
              bar: root.bar
              minimum: 1
              maximum: 100
              integer: true
              value: root.selectedBar.width
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.tokens.disabledOpacity
              onReleased: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarWidth(root.selectedDisplay.name, Math.round(value))
              }
            }
            Caption {
              visible: Number(root.selectedBar.width) < root.selectedMinimumWidth
              anchors.left: parent.left
              anchors.leftMargin: root.tokens.space2
              anchors.bottom: parent.bottom
              anchors.bottomMargin: root.tokens.space1
              width: parent.width - root.tokens.space2 * 2
              text: "Minimum " + root.selectedMinimumWidth + "% — bar items overlap."
              color: Commons.Color.urgent
              elide: Text.ElideRight
            }
            Ui.PanelSeparator {
              anchors.bottom: parent.bottom
              width: parent.width
              foreground: Commons.Color.popups.text
            }
          }

          Item {
            id: backgroundRow
            width: parent.width
            height: controlFrame.height / 5
            PanelUi.ControlLabel { text: "BACKGROUND" }
            Ui.Dropdown {
              id: backgroundDropdown
              objectName: "barBackgroundDropdown"
              anchors.left: parent.left
              anchors.leftMargin: root.tokens.space2
              anchors.right: parent.right
              anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.controlHeight
              showLabel: false
              options: [
                { value: "solid", label: "Solid color" },
                { value: "transparent", label: "Transparent" },
                { value: "blur", label: "Blur" }
              ]
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.tokens.disabledOpacity
              onChanged: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarBackground(root.selectedDisplay.name, value)
              }
            }
            Binding {
              target: backgroundDropdown
              property: "value"
              value: root.selectedBar.background
            }
            Ui.PanelSeparator {
              anchors.bottom: parent.bottom
              width: parent.width
              foreground: Commons.Color.popups.text
            }
          }

          Item {
            id: styleRow
            width: parent.width
            height: controlFrame.height / 5
            PanelUi.ControlLabel { text: "STYLE" }
            Ui.Dropdown {
              id: styleDropdown
              objectName: "barStyleDropdown"
              anchors.left: parent.left
              anchors.leftMargin: root.tokens.space2
              anchors.right: parent.right
              anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.controlHeight
              showLabel: false
              options: [
                { value: "default", label: "Omarchy default" },
                { value: "pill", label: "Pill" }
              ]
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.tokens.disabledOpacity
              onChanged: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarStyle(root.selectedDisplay.name, value)
              }
            }
            Binding {
              target: styleDropdown
              property: "value"
              value: root.selectedBar.style
            }
          }
        }
      }
    }
  }

  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
  Item {
    width: parent.width; height: Style.space(64)
    Text {
      objectName: "barToggleError"
      anchors.left: parent.left; anchors.leftMargin: root.pad
      anchors.right: parent.right; anchors.rightMargin: root.pad
      anchors.verticalCenter: parent.verticalCenter
      text: layoutCanvas.barToggleError
      textFormat: Text.PlainText
      color: Commons.Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
