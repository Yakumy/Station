import QtQuick
import qs.Ui as Ui
import qs.Commons
import "." as Station

Grid {
  id: root
  property var bar: null
  property int stationNumber: 1
  property bool opened: false
  property alias anchorItem: logoButton
  readonly property bool nativeContentSized: true
  signal pressed()

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property real contentFontSize: bar && "effectiveContentSize" in bar
    ? bar.effectiveContentSize : Style.font.body
  readonly property real controlMargin: Style.spaceReal(7.5)
  readonly property rect menuInk: menuTextMetrics.tightBoundingRect
  // Match the menu's painted height, rather than its font's em square.
  readonly property real logoSize: menuInk.height
  readonly property real menuSlotWidth: menuTextMetrics.advanceWidth + controlMargin * 2
  readonly property real inkGap: menuSlotWidth - Math.round(controlMargin) - menuInk.x - menuInk.width + controlMargin

  columns: vertical ? 1 : 2
  spacing: 0

  FontMetrics {
    id: menuMetrics
    font.family: "omarchy"
    font.pixelSize: root.contentFontSize
  }

  TextMetrics {
    id: menuTextMetrics
    font: menuMetrics.font
    text: "\ue900"
  }

  Ui.WidgetButton {
    id: logoButton
    bar: root.bar
    text: "Station"
    tooltipText: "Station"
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 7.5
    fixedWidth: root.vertical ? barSize : root.logoSize + root.controlMargin * 2
    fixedHeight: root.vertical ? menuMetrics.height + scaledVerticalPadding * 2 : barSize
    onPressed: root.pressed()

    Station.StationMark {
      width: root.logoSize
      height: root.logoSize
      x: (parent.width - width) / 2
      // WidgetButton centers the font line box. Match the ink inside it.
      y: Math.round((parent.height - menuMetrics.height) / 2) + menuMetrics.ascent + root.menuInk.y
      tint: logoButton.foreground
    }

    Rectangle {
      visible: root.opened
      width: root.vertical ? Math.max(1, Style.space(2)) : parent.width
      height: root.vertical ? parent.height : Math.max(1, Style.space(2))
      x: root.vertical && root.bar.position === "right" ? 0 : parent.width - width
      y: root.vertical ? 0 : parent.height - height
      color: Color.accent
      radius: Style.cornerRadius
    }
  }

  Ui.WidgetButton {
    id: stationButton
    bar: root.bar
    text: "S" + root.stationNumber
    tooltipText: "Station"
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 7.5
    fontSize: root.contentFontSize
    fixedWidth: root.vertical ? barSize : indicatorInk.width + root.inkGap
    onPressed: root.pressed()

    FontMetrics {
      id: indicatorMetrics
      font.family: stationButton.fontFamily
      font.pixelSize: stationButton.fontSize
    }
    TextMetrics {
      id: indicatorTextMetrics
      font: indicatorMetrics.font
      text: stationButton.text
    }
    readonly property rect indicatorInk: indicatorTextMetrics.tightBoundingRect

    Text {
      text: stationButton.text
      textFormat: Text.PlainText
      font: indicatorMetrics.font
      color: stationButton.foreground
      renderType: Text.NativeRendering
      // Align painted bounds, including S10, without translating the hit area.
      x: root.vertical ? (parent.width - stationButton.indicatorInk.width) / 2 - stationButton.indicatorInk.x
        : root.inkGap - root.controlMargin - stationButton.indicatorInk.x
      y: root.vertical ? (parent.height - stationButton.indicatorInk.height) / 2 - indicatorMetrics.ascent - stationButton.indicatorInk.y
        : Math.round((parent.height - menuMetrics.height) / 2) + menuMetrics.ascent + root.menuInk.y
          + (root.menuInk.height - stationButton.indicatorInk.height) / 2 - indicatorMetrics.ascent - stationButton.indicatorInk.y
    }
  }
}
