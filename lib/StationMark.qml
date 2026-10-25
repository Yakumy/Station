import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: stationMark
  property color tint: Color.popups.text
  implicitWidth: Style.space(22)
  implicitHeight: Style.space(22)

  // Vector geometry from assets/station-main-logo-mask.svg. Keep this in
  // the scene graph: no image decode, tint texture, or raster layer to enlarge.
  Shape {
    width: 516
    height: 515
    preferredRendererType: Shape.CurveRenderer
    transform: Scale {
      xScale: stationMark.width / 516
      yScale: stationMark.height / 515
    }
    ShapePath {
      fillColor: stationMark.tint
      strokeWidth: -1
      PathSvg { path: "M200.409 147.959h115.967v44.0382h-115.967Z M54.5508 240.439L117.672 184.657L152.903 198.603L91.9832 256.586L54.5508 240.439Z M457.5 243.375L396.581 184.657L362.084 197.869L421.535 257.32L457.5 243.375Z" }
    }
    ShapePath {
      fillColor: "transparent"
      strokeColor: stationMark.tint
      strokeWidth: 35
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.FlatCap
      PathSvg { path: "M17.5 263.433L137.791 148.228M17.5 263.433L137.101 364.842M497.973 263.433V118.219L375.959 17.5H137.791L17.5 118.219L17.5 263.433M497.973 263.433V387.607C497.973 387.607 423.609 448.381 375.959 496.604C282.679 496.604 137.101 496.604 137.101 496.604L17.5 387.607L17.5 263.433M137.791 148.228H375.959M137.791 148.228V17.5M375.959 148.228L497.973 263.433M375.959 148.228L375.959 17.5M497.973 263.433L375.959 364.842M375.959 364.842H137.101M375.959 364.842C375.959 364.842 375.959 439.491 375.959 496.604M137.101 364.842V496.604" }
    }
  }
}
