import QtQuick
import qs.Ui as Ui
import qs.Commons

// Match the inset and width of the sliders and row buttons.
Ui.Dropdown {
  width: (parent.width - Style.space(8) * 2) * 0.99
  anchors.centerIn: parent
}
