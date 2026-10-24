import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "." as Station

Column {
  id: root
  required property var panelRoot
  readonly property var service: panelRoot.service
  readonly property var selectedDisplay: panelRoot.selectedDisplay
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
  readonly property int selectedContentSize: Math.max(selectedMinimumContentSize,
    Math.min(selectedHeight, selectedRequestedContentSize))
  readonly property real pad: panelRoot.regionPadH
  spacing: 0

  component Caption: Text {
    color: root.panelRoot.textDim
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
          foreground: root.panelRoot.textPrimary
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "SELECT A SIDE"
          color: root.panelRoot.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Station.BarLayout {
        width: parent.width - root.pad * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        panelRoot: root.panelRoot
        selectedDisplayName: root.selectedDisplay ? root.selectedDisplay.name : ""
        onDisplaySelected: function(name) { root.panelRoot.selectDisplay(name) }
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
          color: root.panelRoot.textPrimary
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      Ui.BorderSurface {
        id: controlFrame
        width: parent.width - Style.space(28) * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius

        Column {
          anchors.fill: parent
          spacing: 0

          Item {
            id: contentSizeRow
            width: parent.width
            height: controlFrame.height / 5
            Caption {
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: "CONTENT SIZE"
            }
            Caption {
              anchors.right: parent.right
              anchors.rightMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: root.selectedContentSize + " px"
            }
            Ui.PanelSlider {
              width: parent.width - root.panelRoot.space3 * 2
              height: implicitHeight
              anchors.centerIn: parent
              bar: root.panelRoot.bar
              minimum: root.selectedMinimumContentSize
              maximum: Math.max(root.selectedMinimumContentSize, root.selectedHeight)
              integer: true
              value: root.selectedContentSize
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.panelRoot.disabledOpacity
              onReleased: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarContentSize(root.selectedDisplay.name, Math.round(value))
              }
            }
            Caption {
              visible: root.selectedRequestedContentSize > root.selectedHeight
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.bottom: parent.bottom
              anchors.bottomMargin: root.panelRoot.space1
              width: parent.width - root.panelRoot.space3 * 2
              text: "Maximum " + root.selectedHeight + " px — content exceeds bar height."
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
            id: widthRow
            width: parent.width
            height: controlFrame.height / 5
            Caption {
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: "WIDTH"
            }
            Caption {
              anchors.right: parent.right
              anchors.rightMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: root.selectedBar.width + "%"
            }
            Ui.PanelSlider {
              width: parent.width - root.panelRoot.space3 * 2
              height: implicitHeight
              anchors.centerIn: parent
              bar: root.panelRoot.bar
              minimum: 1
              maximum: 100
              integer: true
              value: root.selectedBar.width
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.panelRoot.disabledOpacity
              onReleased: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarWidth(root.selectedDisplay.name, Math.round(value))
              }
            }
            Caption {
              visible: Number(root.selectedBar.width) < root.selectedMinimumWidth
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.bottom: parent.bottom
              anchors.bottomMargin: root.panelRoot.space1
              width: parent.width - root.panelRoot.space3 * 2
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
            id: heightRow
            width: parent.width
            height: controlFrame.height / 5
            Caption {
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: "HEIGHT"
            }
            Caption {
              anchors.right: parent.right
              anchors.rightMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: root.selectedHeight + " px"
            }
            Ui.PanelSlider {
              width: parent.width - root.panelRoot.space3 * 2
              height: implicitHeight
              anchors.centerIn: parent
              bar: root.panelRoot.bar
              minimum: root.selectedMinimumHeight
              maximum: root.selectedMaximumHeight
              integer: true
              value: root.selectedHeight
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.panelRoot.disabledOpacity
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
            id: backgroundRow
            width: parent.width
            height: controlFrame.height / 5
            Caption {
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: "BACKGROUND"
            }
            Ui.Dropdown {
              id: backgroundDropdown
              objectName: "barBackgroundDropdown"
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.right: parent.right
              anchors.rightMargin: root.panelRoot.space3
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.controlHeight
              showLabel: false
              options: [
                { value: "solid", label: "Solid color" },
                { value: "transparent", label: "Transparent" },
                { value: "blur", label: "Blur" }
              ]
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.panelRoot.disabledOpacity
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
            Caption {
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: "STYLE"
            }
            Ui.Dropdown {
              id: styleDropdown
              objectName: "barStyleDropdown"
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.right: parent.right
              anchors.rightMargin: root.panelRoot.space3
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.controlHeight
              showLabel: false
              options: [
                { value: "default", label: "Omarchy default" },
                { value: "pill", label: "Pill" }
              ]
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.panelRoot.disabledOpacity
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
  Item { width: parent.width; height: Style.space(64) }
}
