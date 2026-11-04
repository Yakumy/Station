import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model
import "Windows.js" as Windows

Ui.BorderSurface {
  id: canvas
  objectName: "windowsLayout"
  required property var panelRoot
  property var values: ({})
  property bool swapped: false
  property bool animateSwap: false
  readonly property var service: panelRoot.service
  readonly property var displays: service ? service.displayDraft : []
  readonly property real horizontalInset: width * 0.1
  readonly property real verticalInset: height * 0.1
  readonly property real monitorGap: Style.spacing.sm
  readonly property real barEdgeGap: Style.spacing.sm
  clip: true
  color: Commons.Color.popups.background
  borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
  radius: Style.cornerRadius

  readonly property var bounds: {
    if (!displays.length) return { x: 0, y: 0, width: 1, height: 1 }
    var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
    displays.forEach(function(display) {
      var size = Model.logicalSize(display)
      left = Math.min(left, display.x); top = Math.min(top, display.y)
      right = Math.max(right, display.x + size.width); bottom = Math.max(bottom, display.y + size.height)
    })
    return { x: left, y: top, width: right - left, height: bottom - top }
  }
  readonly property real zoom: Math.max(0.001, Math.min(
    (width - 2 * horizontalInset) / Math.max(1, bounds.width),
    (height - 2 * verticalInset) / Math.max(1, bounds.height)))
  readonly property real originX: (width - bounds.width * zoom) / 2
  readonly property real originY: (height - bounds.height * zoom) / 2

  Canvas {
    anchors.fill: parent
    opacity: 0.22
    property color dotColor: Commons.Color.popups.text
    onDotColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var context = getContext("2d")
      context.clearRect(0, 0, width, height)
      context.fillStyle = dotColor
      var gap = Style.space(16), radius = Math.max(Style.space(0.7), 0.5)
      for (var x = gap; x < width; x += gap) for (var y = gap; y < height; y += gap) {
        context.beginPath(); context.arc(x, y, radius, 0, Math.PI * 2); context.fill()
      }
    }
  }

  Repeater {
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      readonly property bool isSelected: false
      readonly property bool outputEnabled: canvas.service
        ? canvas.service.displayEnabled(modelData.name) : modelData.enabled
      readonly property var barSetting: canvas.service
        ? canvas.service.monitorBar(modelData.name)
        : ({ enabled: true, position: "top", width: 100, height: 0, background: "solid", style: "default", contentSize: 0 })
      readonly property int minimumBarWidth: canvas.service
        ? canvas.service.monitorBarMinimum(modelData.name) : 1
      readonly property real effectiveBarWidth: Math.max(Number(barSetting.width) || 100, minimumBarWidth) / 100
      readonly property int defaultBarHeight: barSetting.position === "left" || barSetting.position === "right"
        ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
      readonly property real maximumBarHeight: Math.max(defaultBarHeight,
        canvas.service ? canvas.service.monitorBarMaximumHeight(modelData.name)
          : Math.floor(Math.min(Number(modelData.width), Number(modelData.height)) * 0.05))
      readonly property real effectiveBarHeight: Math.max(defaultBarHeight,
        Math.min(maximumBarHeight, Number(barSetting.height) > 0 ? Number(barSetting.height) : defaultBarHeight))
      readonly property real nameInset: canvas.barEdgeGap
        + Math.max(2, maximumBarHeight * canvas.zoom) + Style.spacing.sm
      x: canvas.originX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom
        + canvas.monitorGap / 2
      y: canvas.originY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom
        + canvas.monitorGap / 2
      width: Math.max(1, logicalSize.width * canvas.zoom - canvas.monitorGap)
      height: Math.max(1, logicalSize.height * canvas.zoom - canvas.monitorGap)
      z: isSelected ? 1 : 0
      color: isSelected ? Commons.Color.menu.selectedBackground : Commons.Color.popups.background
      borderSpec: Border.flat(isSelected
        ? Commons.Color.accent
        : Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent).color,
        isSelected ? Math.max(2, Style.normalBorderWidth) : Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius
      opacity: outputEnabled ? 1 : canvas.panelRoot.disabledOpacity

      Rectangle {
        id: barPreview
        objectName: "barPreview-" + monitorCard.modelData.name
        visible: monitorCard.barSetting.enabled
        color: monitorCard.barSetting.style === "pill" ? "transparent" : canvas.panelRoot.textDim
        radius: Style.cornerRadius
        readonly property bool side: monitorCard.barSetting.position === "left"
          || monitorCard.barSetting.position === "right"
        readonly property real topInset: canvas.barEdgeGap
        readonly property real bottomInset: canvas.barEdgeGap
        width: side ? Math.max(2, monitorCard.effectiveBarHeight * canvas.zoom)
          : Math.max(1, (parent.width - canvas.barEdgeGap * 2) * monitorCard.effectiveBarWidth)
        height: side
          ? Math.max(1, (parent.height - topInset - bottomInset) * monitorCard.effectiveBarWidth)
          : Math.max(2, monitorCard.effectiveBarHeight * canvas.zoom)
        x: monitorCard.barSetting.position === "left" ? canvas.barEdgeGap
          : monitorCard.barSetting.position === "right" ? parent.width - width - canvas.barEdgeGap
          : (parent.width - width) / 2
        y: monitorCard.barSetting.position === "top" ? topInset
          : monitorCard.barSetting.position === "bottom" ? parent.height - height - bottomInset
          : topInset + (parent.height - topInset - bottomInset - height) / 2

        Repeater {
          model: monitorCard.barSetting.style === "pill" ? [0, 1, 2] : []
          delegate: Rectangle {
            required property int modelData
            readonly property real segmentLength: barPreview.side ? barPreview.height : barPreview.width
            readonly property real segmentStart: modelData === 0 ? 0
              : modelData === 1 ? segmentLength * 0.41 : segmentLength * 0.74
            readonly property real segmentShare: modelData === 1 ? 0.18 : 0.26
            x: barPreview.side ? 0 : segmentStart
            y: barPreview.side ? segmentStart : 0
            width: barPreview.side ? barPreview.width : segmentLength * segmentShare
            height: barPreview.side ? segmentLength * segmentShare : barPreview.height
            color: canvas.panelRoot.textDim
            radius: Math.min(width, height) / 2
          }
        }
      }

      Text {
        x: Style.spacing.sm; y: Style.spacing.sm
        width: parent.width - Style.spacing.sm * 2
        text: monitorCard.modelData.name
        color: canvas.panelRoot.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }
  function windowRect(monitorIndex, next) {
    var display = displays[monitorIndex]
    if (!display) return {x:0,y:0,width:0,height:0}
    var size = Model.logicalSize(display)
    var bar = service.monitorBar(display.name)
    var gaps = Windows.gaps(values, bar)
    var minimum = bar.position === "left" || bar.position === "right" ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
    var effective = Math.max(minimum, Math.min(service.monitorBarMaximumHeight(display.name), Number(bar.height) || minimum))
    var thickness = bar.enabled ? Math.max(2, effective * zoom) + barEdgeGap * 2 : 0
    var x = originX + display.x * zoom - bounds.x * zoom + monitorGap / 2
    var y = originY + display.y * zoom - bounds.y * zoom + monitorGap / 2
    var w = size.width * zoom - monitorGap, h = size.height * zoom - monitorGap
    var left = gaps.left * zoom + (bar.position === "left" ? thickness : 0)
    var right = gaps.right * zoom + (bar.position === "right" ? thickness : 0)
    var top = Math.max(Style.space(22), gaps.top * zoom + (bar.position === "top" ? thickness : 0))
    var bottom = gaps.bottom * zoom + (bar.position === "bottom" ? thickness : 0)
    var gap = values.innerGap * zoom
    var available = Math.max(0, w - left - right - gap)
    var first = available * values.split / 100
    return {x:x + left + (next ? 0 : first + gap), y:y + top,
      width:next ? first : available - first, height:Math.max(0,h - top - bottom)}
  }
  Repeater {
    model: canvas.displays.length * 2
    Rectangle {
      required property int index
      objectName: "windowPreview-" + index
      readonly property int home: Math.floor(index / 2)
      readonly property bool nextWindow: index % 2 === 0
      readonly property int destination: !nextWindow && canvas.swapped && canvas.displays.length > 1
        ? (home === 0 ? 1 : home === 1 ? 0 : home) : home
      readonly property var rect: canvas.windowRect(destination, nextWindow)
      x: rect.x; y: rect.y; width: rect.width; height: rect.height
      opacity: canvas.service.displayEnabled(canvas.displays[destination].name) ? 1 : canvas.panelRoot.disabledOpacity
      color: Commons.Color.popups.background
      border.color: canvas.panelRoot.textDim
      border.width: Style.normalBorderWidth
      radius: canvas.values.rounding * canvas.zoom
      Behavior on x { enabled: canvas.animateSwap; NumberAnimation { duration: canvas.values.speed > 0 ? 400 / canvas.values.speed : 0; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: canvas.animateSwap; NumberAnimation { duration: canvas.values.speed > 0 ? 400 / canvas.values.speed : 0; easing.type: Easing.OutCubic } }
      Text {
        anchors.centerIn: parent
        width: Math.max(0,parent.width - Style.spacing.sm * 2)
        horizontalAlignment: Text.AlignHCenter
        text: nextWindow ? "NEXT WINDOW" : "WINDOW"
        elide: Text.ElideRight
        color: canvas.panelRoot.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

}
