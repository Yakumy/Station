import QtQuick
import qs.Commons
import qs.Commons as Commons

// The dotted background every layout canvas draws.
Canvas {
  id: root
  property real gap: Style.space(16)
  anchors.fill: parent
  opacity: 0.22
  property color dotColor: Commons.Color.popups.text
  onDotColorChanged: requestPaint()
  onGapChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onPaint: {
    var context = getContext("2d")
    context.clearRect(0, 0, width, height)
    context.fillStyle = dotColor
    var radius = Math.max(Style.space(0.7), 0.5)
    for (var x = root.gap; x < width; x += root.gap) for (var y = root.gap; y < height; y += root.gap) {
      context.beginPath()
      context.arc(x, y, radius, 0, Math.PI * 2)
      context.fill()
    }
  }
}
