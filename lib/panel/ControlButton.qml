import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Secondary row actions share the same safe inset as the Display sliders.
Ui.Button {
  anchors.left: parent.left
  anchors.right: parent.right
  anchors.leftMargin: Style.space(8)
  anchors.rightMargin: Style.space(8)
  anchors.verticalCenter: parent.verticalCenter
  height: Style.spacing.controlHeight
  radius: Style.cornerRadius
  bordered: true
  foreground: Commons.Color.popups.text
}
