import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "../displays/Model.js" as Model
import "ColorMatch.js" as ColorMatch

// Read-only monitor arrangement for Color Match. A click selects a monitor; the
// card says whether it has a profile.
Ui.BorderSurface {
  id: canvas
  required property var tokens
  required property var service
  property string selectedDisplayName: ""
  signal displaySelected(string name)
  readonly property var displays: service ? service.displayDraft : []
  readonly property var colorMatch: service && service.colorMatch ? service.colorMatch : ({ values: {}, hdr: [] })
  readonly property real horizontalInset: width * 0.1
  readonly property real verticalInset: Math.max(height * 0.1, Style.font.caption + Style.spacing.sm * 2)
  readonly property real monitorGap: Style.spacing.sm
  clip: true
  color: Commons.Color.popups.background
  borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
  radius: Style.cornerRadius

  readonly property var bounds: {
    if (!displays.length) return { x: 0, y: 0, width: 1, height: 1 }
    var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
    displays.forEach(function(display) {
      var size = Model.logicalSize(display)
      left = Math.min(left, display.x); top = Math.min(top, display.y)
      right = Math.max(right, display.x + size.width); bottom = Math.max(bottom, display.y + size.height)
    })
    return { x: left, y: top, width: right - left, height: bottom - top }
  }
  readonly property real zoom: Math.max(0.001, Math.min(
    (width - 2 * horizontalInset) / Math.max(1, bounds.width),
    (height - 2 * verticalInset) / Math.max(1, bounds.height)))
  readonly property real originX: (width - bounds.width * zoom) / 2
  readonly property real originY: (height - bounds.height * zoom) / 2

  Canvas {
    anchors.fill: parent
    opacity: 0.22
    property color dotColor: Commons.Color.popups.text
    onDotColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var context = getContext("2d")
      context.clearRect(0, 0, width, height)
      context.fillStyle = dotColor
      var gap = Style.space(16), radius = Math.max(Style.space(0.7), 0.5)
      for (var x = gap; x < width; x += gap) for (var y = gap; y < height; y += gap) {
        context.beginPath(); context.arc(x, y, radius, 0, Math.PI * 2); context.fill()
      }
    }
  }

  Repeater {
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      objectName: "colorMonitor-" + modelData.name
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      readonly property bool isSelected: canvas.selectedDisplayName === modelData.name
      readonly property bool outputEnabled: canvas.service
        ? canvas.service.displayEnabled(modelData.name) : modelData.enabled
      readonly property bool hdr: (canvas.colorMatch.hdr || []).indexOf(modelData.name) !== -1
      readonly property bool adjusted: !ColorMatch.isNeutral((canvas.colorMatch.values || {})[modelData.name])
      x: canvas.originX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom + canvas.monitorGap / 2
      y: canvas.originY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom + canvas.monitorGap / 2
      width: Math.max(1, logicalSize.width * canvas.zoom - canvas.monitorGap)
      height: Math.max(1, logicalSize.height * canvas.zoom - canvas.monitorGap)
      z: isSelected ? 1 : 0
      color: isSelected ? Commons.Color.menu.selectedBackground : Commons.Color.popups.background
      borderSpec: Border.flat(isSelected
        ? Commons.Color.accent
        : Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent).color,
        isSelected ? Math.max(2, Style.normalBorderWidth) : Math.max(1, Style.normalBorderWidth))
      radius: 0
      opacity: outputEnabled ? 1 : canvas.tokens.disabledOpacity

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: canvas.displaySelected(monitorCard.modelData.name)
      }

      Column {
        anchors.centerIn: parent
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
