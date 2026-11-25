import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "../displays/Model.js" as Model

// One monitor of a MonitorCanvas, at its place and size.
Ui.BorderSurface {
  required property var layout
  required property var modelData
  property bool isSelected: false
  property bool outputEnabled: true
  // Where a drag holds it, away from its place.
  property real offsetX: 0
  property real offsetY: 0
  property var outline: isSelected ? Commons.Color.accent
    : Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent).color
  readonly property var logicalSize: Model.logicalSize(modelData)
  x: layout.originX + layout.panX + (Number(modelData.x) - layout.bounds.x) * layout.zoom
    + layout.monitorGap / 2 + offsetX
  y: layout.originY + layout.panY + (Number(modelData.y) - layout.bounds.y) * layout.zoom
    + layout.monitorGap / 2 + offsetY
  width: Math.max(1, logicalSize.width * layout.zoom - layout.monitorGap)
  height: Math.max(1, logicalSize.height * layout.zoom - layout.monitorGap)
  z: isSelected ? 1 : 0
  color: isSelected ? Commons.Color.menu.selectedBackground : Commons.Color.popups.background
  borderSpec: Border.flat(outline,
    isSelected ? Math.max(2, Style.normalBorderWidth) : Math.max(1, Style.normalBorderWidth))
  radius: 0
  opacity: outputEnabled || !layout.tokens ? 1 : layout.tokens.disabledOpacity
}
