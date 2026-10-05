import QtQuick
import qs.Ui as Ui
import qs.Commons
import "Model.js" as Model

Ui.BorderSurface {
  id: canvas
  property var service: null
  property string selectedDisplayName: ""
  signal displaySelected(string name)
  height: Style.space(190)
  color: Color.popups.background
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
  radius: Style.cornerRadius
  readonly property real inset: Style.spacing.md
  readonly property var displays: service ? service.displayDraft : []
  readonly property var bounds: {
    if (!displays.length) return { x: 0, y: 0, width: 1, height: 1, sumWidth: 1, sumHeight: 1 }
    var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
    var sumWidth = 0, sumHeight = 0
    displays.forEach(function(display) {
      var size = Model.logicalSize(display)
      left = Math.min(left, display.x); top = Math.min(top, display.y)
      right = Math.max(right, display.x + size.width); bottom = Math.max(bottom, display.y + size.height)
      sumWidth += size.width; sumHeight += size.height
    })
    return { x: left, y: top, width: right - left, height: bottom - top, sumWidth: sumWidth, sumHeight: sumHeight }
  }
  // Reserve room for both horizontal and vertical arrangements. Keep this
  // transform unchanged throughout a gesture by committing only on release.
  readonly property real zoom: Math.max(0.001, Math.min(0.09,
    (width - 2 * inset) / Math.max(bounds.width, bounds.sumWidth),
    (height - 2 * inset) / Math.max(bounds.height, bounds.sumHeight)))
  readonly property real originX: (width - bounds.width * zoom) / 2
  readonly property real originY: (height - bounds.height * zoom) / 2

  function commitPosition(display, x, y) {
    if (!service || service.state !== "idle") return
    var snapped = Model.snapPosition(display, x, y, displays, Style.space(12) / zoom)
    // This function belongs to the canvas, which survives rebuilding the
    // Repeater. Never continue a service mutation from a destroyed delegate.
    if (service.setDisplayPosition(display.name, snapped.x, snapped.y) === "ok") service.previewLayout()
  }

  Repeater {
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      property real offsetX: 0
      property real offsetY: 0
      x: canvas.originX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom + offsetX
      y: canvas.originY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom + offsetY
      width: logicalSize.width * canvas.zoom
      height: logicalSize.height * canvas.zoom
      z: pointer.pressed ? 1 : 0
      color: canvas.selectedDisplayName === modelData.name ? Color.menu.selectedBackground : Color.menu.background
      borderSpec: Border.controlSpec(canvas.selectedDisplayName === modelData.name ? "selected" : "normal", Color.menu.text, Color.accent)
      radius: Style.cornerRadius
      opacity: modelData.enabled ? 1 : 0.5
      Text {
        anchors.centerIn: parent
        text: modelData.name + "\nLane " + modelData.lane
        horizontalAlignment: Text.AlignHCenter
        color: canvas.selectedDisplayName === modelData.name ? Color.menu.selectedText : Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: canvas.service && canvas.service.state === "idle"
        property point startPointer
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: function(mouse) {
          startPointer = mapToItem(canvas, mouse.x, mouse.y)
          canvas.displaySelected(modelData.name)
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var position = mapToItem(canvas, mouse.x, mouse.y)
          monitorCard.offsetX = position.x - startPointer.x
          monitorCard.offsetY = position.y - startPointer.y
        }
        onCanceled: { monitorCard.offsetX = 0; monitorCard.offsetY = 0 }
        onReleased: {
          var dx = monitorCard.offsetX, dy = monitorCard.offsetY
          var display = modelData
          monitorCard.offsetX = 0; monitorCard.offsetY = 0
          if (Math.hypot(dx, dy) < Qt.styleHints.startDragDistance) return
          canvas.commitPosition(display, Number(display.x) + dx / canvas.zoom, Number(display.y) + dy / canvas.zoom)
        }
      }
    }
  }
}
