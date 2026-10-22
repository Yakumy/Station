import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "." as Station

Column {
  id: root
  required property var panelRoot
  readonly property real pad: panelRoot.regionPadH
  spacing: 0

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
        Ui.PanelSectionHeader {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          text: "BAR"
          foreground: root.panelRoot.textPrimary
        }
      }
      Ui.BorderSurface {
        width: parent.width - Style.space(28) * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius
      }
    }
  }
}
