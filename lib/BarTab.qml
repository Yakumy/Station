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
    ? service.monitorBar(selectedDisplay.name) : ({ enabled: true, position: "top", width: 100, height: 0 })
  readonly property int selectedMinimumWidth: selectedDisplay && service
    ? service.monitorBarMinimum(selectedDisplay.name) : 1
  readonly property int selectedMinimumHeight: selectedBar.position === "left" || selectedBar.position === "right"
    ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int selectedMaximumHeight: selectedDisplay && service
    ? Math.max(selectedMinimumHeight, service.monitorBarMaximumHeight(selectedDisplay.name))
    : selectedMinimumHeight
  readonly property int selectedHeight: Math.max(selectedMinimumHeight, Math.min(selectedMaximumHeight,
    Number(selectedBar.height) > 0 ? Number(selectedBar.height) : selectedMinimumHeight))
  readonly property real pad: panelRoot.regionPadH
  spacing: 0

  component Caption: Text {
    color: root.panelRoot.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  component PositionSelector: Ui.BorderSurface {
    id: selector
    property string value: ""
    property var options: []
    signal changed(string value)
    color: Commons.Color.popups.background
    borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
    radius: Style.cornerRadius
    clip: true

    Row {
      anchors.fill: parent
      anchors.margins: Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Repeater {
        model: selector.options
        delegate: Item {
          required property var modelData
          required property int index
          width: (selector.width - Math.max(1, Style.normalBorderWidth) * 2) / selector.options.length
          height: parent.height
          Ui.Button {
            anchors.fill: parent
            text: modelData.label
            selected: selector.value === modelData.value
            focusable: true
            foreground: Commons.Color.popups.text
            background: Commons.Color.popups.background
            accent: Commons.Color.accent
            onClicked: selector.changed(modelData.value)
          }
          Rectangle {
            visible: index > 0
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Style.normalBorderWidth)
            color: Border.color(Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent))
          }
        }
      }
    }
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
            width: parent.width
            height: controlFrame.height / 5
            Caption {
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.top: parent.top
              anchors.topMargin: root.panelRoot.space2
              text: "POSITION"
            }
            PositionSelector {
              anchors.left: parent.left
              anchors.leftMargin: root.panelRoot.space3
              anchors.right: parent.right
              anchors.rightMargin: root.panelRoot.space3
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.controlHeight
              enabled: root.selectedDisplay !== null
              opacity: enabled ? 1 : root.panelRoot.disabledOpacity
              value: root.selectedBar.position
              options: [
                { value: "top", label: "Top" },
                { value: "right", label: "Right" },
                { value: "bottom", label: "Bottom" },
                { value: "left", label: "Left" }
              ]
              onChanged: function(value) {
                if (root.service && root.selectedDisplay)
                  root.service.setMonitorBarPosition(root.selectedDisplay.name, value)
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

          Repeater {
            model: 2
            delegate: Item {
              required property int index
              width: controlFrame.width
              height: controlFrame.height / 5
              Ui.PanelSeparator {
                visible: index < 3
                anchors.bottom: parent.bottom
                width: parent.width
                foreground: Commons.Color.popups.text
              }
            }
          }
        }
      }
    }
  }

  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
  Item { width: parent.width; height: Style.space(64) }
}
