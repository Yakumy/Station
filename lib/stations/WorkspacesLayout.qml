import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "../displays/Model.js" as Model

// Read-only monitor layout for the Workspaces tab. Positions follow Displays and
// cannot be dragged or selected here. Each managed output shows its role and the
// workspaces the chosen mode assigns to it.
Ui.BorderSurface {
  id: canvas
  objectName: "workspacesLayout"
  property var service: null
  property var tokens: null
  // `assigned[i]` lists the numbers output i of `outputs` shows.
  property var outputs: []
  property var assigned: []
  clip: true
  color: Commons.Color.popups.background
  borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
  radius: Style.cornerRadius
  readonly property real gridStep: Style.space(16)
  readonly property real monitorGap: Style.spacing.sm
  readonly property real horizontalInset: width * 0.1
  readonly property real verticalInset: height * 0.1
  readonly property var displays: service ? service.displayDraft : []
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
  readonly property real fitZoom: Math.max(0.001, Math.min(
    (width - 2 * horizontalInset) / Math.max(1, bounds.width),
    (height - 2 * verticalInset) / Math.max(1, bounds.height)))
  property real zoomFactor: 1
  property real panX: 0
  property real panY: 0
  readonly property real zoom: fitZoom * zoomFactor
  readonly property real originX: (width - bounds.width * zoom) / 2
  readonly property real originY: (height - bounds.height * zoom) / 2

  function zoomAt(factor, px, py) {
    var next = Math.max(0.5, Math.min(4, zoomFactor * factor))
    if (next === zoomFactor) return
    var worldX = (px - originX - panX) / zoom
    var worldY = (py - originY - panY) / zoom
    zoomFactor = next
    panX = px - originX - worldX * zoom
    panY = py - originY - worldY * zoom
  }

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
      var gap = canvas.gridStep
      var radius = Math.max(Style.space(0.7), 0.5)
      for (var x = gap; x < width; x += gap) for (var y = gap; y < height; y += gap) {
        context.beginPath()
        context.arc(x, y, radius, 0, Math.PI * 2)
        context.fill()
      }
    }
  }

  // Pan and zoom only. Cards take no pointer input, so the layout stays locked.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real lastX: 0
    property real lastY: 0
    onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      canvas.panX += mouse.x - lastX
      canvas.panY += mouse.y - lastY
      lastX = mouse.x; lastY = mouse.y
    }
    onWheel: function(wheel) {
      canvas.zoomAt(wheel.angleDelta.y > 0 ? 1.15 : 1 / 1.15, wheel.x, wheel.y)
      wheel.accepted = true
    }
  }

  Repeater {
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      objectName: "workspaceMonitor-" + modelData.name
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      readonly property int outputIndex: canvas.outputs.indexOf(modelData.name)
      readonly property var numbers: outputIndex !== -1 ? canvas.assigned[outputIndex] || [] : []
      x: canvas.originX + canvas.panX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom
        + canvas.monitorGap / 2
      y: canvas.originY + canvas.panY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom
        + canvas.monitorGap / 2
      width: Math.max(1, logicalSize.width * canvas.zoom - canvas.monitorGap)
      height: Math.max(1, logicalSize.height * canvas.zoom - canvas.monitorGap)
      color: Commons.Color.popups.background
      borderSpec: Border.flat(Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent).color,
        Math.max(1, Style.normalBorderWidth))
      radius: 0
      opacity: outputIndex !== -1 || !canvas.tokens ? 1 : canvas.tokens.disabledOpacity

      Flow {
        objectName: "workspaceBadges-" + monitorCard.modelData.name
        x: Style.spacing.sm
        y: Style.spacing.sm
        width: Math.max(0, parent.width - Style.spacing.sm * 2)
        height: Math.max(0, parent.height - Style.spacing.sm * 2)
        spacing: Style.spacing.xs
        clip: true
        Repeater {
          model: monitorCard.numbers
          delegate: Ui.BorderSurface {
            required property int modelData
            objectName: "workspaceBadge-" + monitorCard.modelData.name + "-" + modelData
            width: Math.max(Style.space(20), badgeLabel.implicitWidth + Style.space(8))
            height: Style.space(20)
            color: Commons.Color.menu.selectedBackground
            borderSpec: Border.flat(Commons.Color.accent, Math.max(1, Style.normalBorderWidth))
            radius: Style.cornerRadius
            Text {
              id: badgeLabel
              anchors.centerIn: parent
              text: String(parent.modelData)
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.spacing.sm
        Text {
          objectName: "workspaceMonitorName-" + monitorCard.modelData.name
          text: monitorCard.modelData.name
          color: canvas.tokens ? canvas.tokens.textDim : Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          objectName: "workspaceMonitorRole-" + monitorCard.modelData.name
          text: monitorCard.outputIndex !== -1 ? "| " + (monitorCard.outputIndex + 1) : "| Off"
          color: canvas.tokens ? canvas.tokens.textDim : Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.sm
    Repeater {
      model: [{ glyph: "-", factor: 1 / 1.2 }, { glyph: "+", factor: 1.2 }]
      delegate: Item {
        required property var modelData
        width: Style.space(23)
        height: Style.space(23)
        Text {
          anchors.centerIn: parent
          text: modelData.glyph
          color: canvas.tokens ? canvas.tokens.textDim : Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: canvas.zoomAt(modelData.factor, canvas.width / 2, canvas.height / 2)
        }
      }
    }
  }
}
