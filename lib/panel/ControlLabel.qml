import QtQuick
import qs.Commons
import qs.Commons as Commons

// Displays is the reference for every control-panel row title.
Text {
  objectName: "controlRowTitle"
  anchors.left: parent.left
  anchors.leftMargin: Style.space(8)
  anchors.top: parent.top
  anchors.topMargin: Style.space(8)
  textFormat: Text.PlainText
  color: Qt.darker(Commons.Color.popups.text, 1.4)
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  font.capitalization: Font.AllUppercase
  elide: Text.ElideRight
}
