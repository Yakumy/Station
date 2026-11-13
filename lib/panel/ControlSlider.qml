import QtQuick
import qs.Ui as Ui
import qs.Commons

Ui.PanelSlider {
  // Keep the entire knob inside the row, including its hover enlargement.
  width: (parent.width - Style.space(8) * 2) * 0.99
  height: implicitHeight
  anchors.centerIn: parent
}
