import QtQuick
import qs.Ui as Ui
import qs.Commons

Ui.PanelSlider {
  // The host track insets by half a knob; extend the hit area so its visible
  // endpoints align with the title, hint and other row controls.
  width: parent.width - Style.space(8) * 2 + knobSize
  height: implicitHeight
  anchors.centerIn: parent
}
