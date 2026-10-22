import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: stationMark
  property color tint: Color.popups.text
  implicitWidth: Style.space(22)
  implicitHeight: Style.space(22)

  Image {
    id: markImage
    anchors.fill: parent
    fillMode: Image.PreserveAspectFit
    // The public mark is green. Its geometry-identical white mask keeps
    // MultiEffect colorization at the exact Omarchy foreground token.
    source: Qt.resolvedUrl("../assets/station-main-logo-mask.svg")
    sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    sourceSize.height: Math.round(height * Screen.devicePixelRatio)
    visible: false
    layer.enabled: true
  }
  MultiEffect {
    anchors.fill: markImage
    source: markImage
    colorization: 1.0
    colorizationColor: stationMark.tint
  }
}
