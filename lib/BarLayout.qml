import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Ui.BorderSurface {
  id: canvas
  required property var panelRoot
  readonly property var service: panelRoot.service
  readonly property var displays: service ? service.displayDraft : []
  readonly property real inset: panelRoot.space4
  clip: true
  color: Commons.Color.popups.background
  borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
  radius: Style.cornerRadius

  readonly property var bounds: {
    if (!displays.length) return { x: 0, y: 0, width: 1, height: 1, sumWidth: 1, sumHeight: 1 }
    var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
    var sumWidth = 0, sumHeight = 0, maxWidth = 0, maxHeight = 0
    displays.forEach(function(display) {
      var size = Model.logicalSize(display)
      left = Math.min(left, display.x); top = Math.min(top, display.y)
      right = Math.max(right, display.x + size.width); bottom = Math.max(bottom, display.y + size.height)
      sumWidth += size.width; sumHeight += size.height
      maxWidth = Math.max(maxWidth, size.width); maxHeight = Math.max(maxHeight, size.height)
    })
    return { x: left, y: top, width: right - left, height: bottom - top,
      sumWidth: Math.max(sumWidth, maxWidth * 2.5), sumHeight: Math.max(sumHeight, maxHeight * 2.5) }
  }
  readonly property real zoom: Math.max(0.001, Math.min(0.06,
    (width - 2 * inset) * 0.85 / Math.max(bounds.width, bounds.sumWidth),
    (height - 2 * inset) * 0.85 / Math.max(bounds.height, bounds.sumHeight)))
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
      readonly property bool outputEnabled: canvas.service
        ? canvas.service.displayEnabled(modelData.name) : modelData.enabled
      readonly property var barSetting: canvas.service
        ? canvas.service.monitorBar(modelData.name) : ({ enabled: true, position: "top" })
      x: canvas.originX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom
      y: canvas.originY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom
      width: logicalSize.width * canvas.zoom
      height: logicalSize.height * canvas.zoom
      color: Commons.Color.popups.background
      borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
      radius: Style.cornerRadius
      opacity: outputEnabled ? 1 : canvas.panelRoot.disabledOpacity

      Rectangle {
        id: barPreview
        visible: monitorCard.barSetting.enabled
        color: Commons.Color.accent
        radius: Style.cornerRadius
        readonly property bool side: monitorCard.barSetting.position === "left"
          || monitorCard.barSetting.position === "right"
        width: side ? Math.max(2, Style.space(3)) : parent.width * 0.58
        height: side ? parent.height * 0.58 : Math.max(2, Style.space(3))
        anchors.horizontalCenter: side ? undefined : parent.horizontalCenter
        anchors.verticalCenter: side ? parent.verticalCenter : undefined
        anchors.left: monitorCard.barSetting.position === "left" ? parent.left : undefined
        anchors.right: monitorCard.barSetting.position === "right" ? parent.right : undefined
        anchors.top: monitorCard.barSetting.position === "top" ? parent.top : undefined
        anchors.bottom: monitorCard.barSetting.position === "bottom" ? parent.bottom : undefined
      }

      Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: canvas.panelRoot.space2
        text: monitorCard.modelData.name
        color: canvas.panelRoot.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width - canvas.panelRoot.space4
      }

      Repeater {
        model: [
          { position: "top", glyph: "↑", x: 0.5, y: 0.24 },
          { position: "right", glyph: "→", x: 0.76, y: 0.5 },
          { position: "bottom", glyph: "↓", x: 0.5, y: 0.76 },
          { position: "left", glyph: "←", x: 0.24, y: 0.5 }
        ]
        delegate: Item {
          required property var modelData
          width: Style.space(28)
          height: Style.space(28)
          x: monitorCard.width * modelData.x - width / 2
          y: monitorCard.height * modelData.y - height / 2
          Text {
            anchors.centerIn: parent
            text: parent.modelData.glyph
            color: monitorCard.barSetting.position === parent.modelData.position
              ? Commons.Color.accent : Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: canvas.service.setMonitorBarPosition(monitorCard.modelData.name, parent.modelData.position)
          }
        }
      }

      Ui.ToggleSwitch {
        anchors.centerIn: parent
        trackHeight: Math.max(Style.space(18), 14)
        checked: monitorCard.barSetting.enabled
        foreground: Commons.Color.popups.text
        accent: Commons.Color.accent
        onToggled: canvas.service.setMonitorBarEnabled(monitorCard.modelData.name, !checked)
      }
    }
  }
}
