import QtQuick
import qs.Ui as Ui
import qs.Commons

Ui.PanelSlider {
  // The shared row inset, so sliders, dropdowns and buttons line up: Style.space(8),
  // plus 0.5% of the rest, at each end. It is rounded up to a whole pixel, so both
  // ends match and the inset never shrinks. That keeps the knob inside the row,
  // including its hover enlargement, even at a small font size, where Omarchy holds
  // the knob at 14 px while the spacing shrinks.
  readonly property real rowInset: Style.space(8) + Math.ceil((parent.width - Style.space(8) * 2) * 0.005)
  x: rowInset
  width: parent.width - rowInset * 2
  height: implicitHeight
  anchors.verticalCenter: parent.verticalCenter
}
