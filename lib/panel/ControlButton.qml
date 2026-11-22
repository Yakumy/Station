import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Secondary row actions share the same safe inset as the Display sliders.
Ui.Button {
  // The shared row inset; see ControlSlider.qml.
  readonly property real rowInset: Style.space(8) + Math.ceil((parent.width - Style.space(8) * 2) * 0.005)
  x: rowInset
  width: parent.width - rowInset * 2
  anchors.verticalCenter: parent.verticalCenter
  height: Style.spacing.controlHeight
  radius: Style.cornerRadius
  bordered: true
  foreground: Commons.Color.popups.text
}
