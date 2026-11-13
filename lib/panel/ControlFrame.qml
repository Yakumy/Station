import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Restore the frame width; controls reserve their own endpoint clearance.
Ui.BorderSurface {
  property bool narrow: false
  readonly property real controlWidth: (parent.width - Style.space(28) * 2 - Style.space(24) * 2) * 1.2 * 0.96
  width: narrow ? parent.width - Style.space(24) * 2 : Math.max(0, Math.min(parent.width - Style.space(8) * 2, controlWidth + Style.space(8) * 2))
  anchors.horizontalCenter: parent.horizontalCenter
  color: Commons.Color.popups.background
  borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
  radius: Style.cornerRadius
}
