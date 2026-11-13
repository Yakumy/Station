import QtQuick
import qs.Commons
import qs.Commons as Commons

Text {
  required property string name
  property bool centerInParent: true
  property color foreground: Qt.darker(Commons.Color.popups.text, 1.4)
  objectName: "monitorName-" + name
  text: name
  textFormat: Text.PlainText
  anchors.horizontalCenter: centerInParent ? parent.horizontalCenter : undefined
  anchors.verticalCenter: centerInParent ? parent.verticalCenter : undefined
  width: centerInParent ? Math.max(0, parent.width - Style.spacing.sm * 2) : implicitWidth
  horizontalAlignment: Text.AlignHCenter
  elide: Text.ElideRight
  color: foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
}
