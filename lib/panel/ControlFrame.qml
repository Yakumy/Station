import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Keep the column split and reduce the previous control width by ten percent.
Ui.BorderSurface {
  readonly property real controlWidth: (parent.width - Style.space(28) * 2 - Style.space(24) * 2) * 1.2 * 0.96 * 0.9
  width: controlWidth + Style.space(8) * 2
  anchors.horizontalCenter: parent.horizontalCenter
  color: Commons.Color.popups.background
  borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
  radius: Style.cornerRadius
}
