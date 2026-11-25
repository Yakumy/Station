import QtQuick
import "../panel" as PanelUi
import qs.Commons
import qs.Commons as Commons
import "ColorMatch.js" as ColorMatch

// Read-only monitor arrangement for Color Match. A click selects a monitor; the
// card says whether it has a profile.
PanelUi.MonitorCanvas {
  id: canvas
  required tokens
  required service
  property string selectedDisplayName: ""
  signal displaySelected(string name)
  readonly property var colorMatch: service && service.colorMatch ? service.colorMatch : ({ values: {}, hdr: [] })

  Repeater {
    model: canvas.displays
    delegate: PanelUi.MonitorCard {
      id: monitorCard
      objectName: "colorMonitor-" + modelData.name
      layout: canvas
      isSelected: canvas.selectedDisplayName === modelData.name
      outputEnabled: canvas.service
        ? canvas.service.displayEnabled(modelData.name) : modelData.enabled
      readonly property bool hdr: (canvas.colorMatch.hdr || []).indexOf(modelData.name) !== -1
      readonly property bool adjusted: !ColorMatch.isNeutral((canvas.colorMatch.values || {})[modelData.name])

      PanelUi.MonitorName { name: monitorCard.modelData.name }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: canvas.displaySelected(monitorCard.modelData.name)
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 + Style.font.caption / 2 + Style.spacing.xs
        width: parent.width - Style.spacing.lg * 2
        spacing: Style.spacing.xs
        Text {
          objectName: "colorState-" + monitorCard.modelData.name
          width: parent.width
          text: monitorCard.hdr ? "HDR" : monitorCard.adjusted ? "Adjusted" : "Original"
          color: monitorCard.adjusted && !monitorCard.hdr ? Commons.Color.accent : canvas.tokens.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
