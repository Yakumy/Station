import QtQuick
import "." as PanelUi
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "../displays/Model.js" as Model

// The monitor arrangement five tabs draw: displayDraft fitted into a dotted frame.
// A layout adds its own MonitorCards. `zoomable` adds pan, wheel zoom and - / +.
Ui.BorderSurface {
  id: canvas
  property var service: null
  property var tokens: null
  property bool zoomable: false
  readonly property var displays: service ? service.displayDraft : []
  // The dotted grid and the Displays drag snap are the same 16px step, so what you
  // see is what you land on.
  readonly property real gridStep: Style.space(16)
  readonly property real monitorGap: Style.spacing.sm
  readonly property real horizontalInset: width * 0.1
  property real verticalInset: Math.max(height * 0.1, Style.font.caption + Style.spacing.sm * 2)
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
  // Default framing keeps about ten percent clear on every canvas edge. Keep
  // this transform unchanged throughout a gesture by committing only on release.
  readonly property real fitZoom: Math.max(0.001, Math.min(
    (width - 2 * horizontalInset) / Math.max(1, bounds.width),
    (height - 2 * verticalInset) / Math.max(1, bounds.height)))
  property real zoomFactor: 1
  property real panX: 0
  property real panY: 0
  readonly property real zoom: fitZoom * zoomFactor
  readonly property real originX: (width - bounds.width * zoom) / 2
  readonly property real originY: (height - bounds.height * zoom) / 2

  function zoomAt(factor, px, py) {
    var next = Math.max(0.5, Math.min(4, zoomFactor * factor))
    if (next === zoomFactor) return
    var worldX = (px - originX - panX) / zoom
    var worldY = (py - originY - panY) / zoom
    zoomFactor = next
    panX = px - originX - worldX * zoom
    panY = py - originY - worldY * zoom
  }

  PanelUi.DotGrid { gap: canvas.gridStep }

  MouseArea {
    anchors.fill: parent
    visible: canvas.zoomable
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real lastX: 0
    property real lastY: 0
    onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      canvas.panX += mouse.x - lastX
      canvas.panY += mouse.y - lastY
      lastX = mouse.x; lastY = mouse.y
    }
    onWheel: function(wheel) {
      canvas.zoomAt(wheel.angleDelta.y > 0 ? 1.15 : 1 / 1.15, wheel.x, wheel.y)
      wheel.accepted = true
    }
  }

  Row {
    visible: canvas.zoomable
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.sm
    z: 5
    Repeater {
      model: canvas.zoomable ? [{ glyph: "-", factor: 1 / 1.2 }, { glyph: "+", factor: 1.2 }] : []
      delegate: Item {
        required property var modelData
        width: Style.space(23)
        height: Style.space(23)
        Text {
          anchors.centerIn: parent
          text: modelData.glyph
          color: Qt.darker(Commons.Color.popups.text, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: canvas.zoomAt(modelData.factor, canvas.width / 2, canvas.height / 2)
        }
      }
    }
  }
}
