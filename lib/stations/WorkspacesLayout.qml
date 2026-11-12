import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "../displays/Model.js" as Model

// Monitor layout for the Workspaces tab. Positions follow Displays and cannot be
// dragged or selected here. Each managed output shows its role and the workspaces
// the draft gives it. Repetitive has − and + on every monitor, Non-repetitive on
// the last one, and Non-repetitive badges drag onto another monitor.
Ui.BorderSurface {
  id: canvas
  objectName: "workspacesLayout"
  property var service: null
  property var tokens: null
  // `assigned[i]` lists the numbers output i of `outputs` shows.
  property var outputs: []
  property var assigned: []
  property string mode: "station"
  // `steps[i]` is `{ shown, down, up }` for output i's − and + buttons.
  property var steps: []
  signal countChangeRequested(string output, int delta)
  signal workspaceMoved(int number, string output)
  readonly property bool draggable: mode === "nonrepetitive"
  // The badge being dragged, its pointer position in the canvas, and the monitor under it.
  property int dragNumber: -1
  property real dragX: 0
  property real dragY: 0
  property string dropOutput: ""
  function outputAt(px, py) {
    for (var i = 0; i < monitorCards.count; i++) {
      var card = monitorCards.itemAt(i)
      if (card && card.outputIndex !== -1 && px >= card.x && px <= card.x + card.width
          && py >= card.y && py <= card.y + card.height) return card.modelData.name
    }
    return ""
  }
  clip: true
  color: Commons.Color.popups.background
  borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
  radius: Style.cornerRadius
  readonly property real gridStep: Style.space(16)
  readonly property real labelHeight: Style.font.caption + Style.spacing.sm
  readonly property real monitorGap: Style.spacing.sm
  readonly property real horizontalInset: width * 0.1
  readonly property real verticalInset: Math.max(height * 0.1, Style.font.caption + Style.spacing.sm * 2)
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

  // Pan and zoom. Monitor cards never move here; only their badges and − and + take input.
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
    id: monitorCards
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      objectName: "workspaceMonitor-" + modelData.name
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      readonly property int outputIndex: canvas.outputs.indexOf(modelData.name)
      readonly property var numbers: outputIndex !== -1 ? canvas.assigned[outputIndex] || [] : []
      readonly property var step: outputIndex !== -1 && canvas.steps[outputIndex] ? canvas.steps[outputIndex]
        : ({ shown: false, down: false, up: false })
      readonly property bool dropTarget: canvas.dragNumber !== -1 && canvas.dropOutput === modelData.name
      x: canvas.originX + canvas.panX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom
        + canvas.monitorGap / 2
      y: canvas.originY + canvas.panY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom
        + canvas.monitorGap / 2 + canvas.labelHeight
      width: Math.max(1, logicalSize.width * canvas.zoom - canvas.monitorGap)
      height: Math.max(1, logicalSize.height * canvas.zoom - canvas.monitorGap - canvas.labelHeight)
      color: Commons.Color.popups.background
      borderSpec: Border.flat(dropTarget ? Commons.Color.accent
        : Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent).color,
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
            id: badge
            required property int modelData
            objectName: "workspaceBadge-" + monitorCard.modelData.name + "-" + modelData
            opacity: canvas.dragNumber === modelData ? 0.4 : 1
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
            MouseArea {
              anchors.fill: parent
              enabled: canvas.draggable
              preventStealing: true
              cursorShape: canvas.draggable ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
              function track(mouse) {
                var point = mapToItem(canvas, mouse.x, mouse.y)
                canvas.dragX = point.x
                canvas.dragY = point.y
                canvas.dropOutput = canvas.outputAt(point.x, point.y)
              }
              onPressed: function(mouse) { canvas.dragNumber = badge.modelData; track(mouse) }
              onPositionChanged: function(mouse) { if (pressed) track(mouse) }
              onReleased: function(mouse) {
                track(mouse)
                var number = canvas.dragNumber
                var output = canvas.dropOutput
                canvas.dragNumber = -1
                canvas.dropOutput = ""
                if (number !== -1 && output !== "" && output !== monitorCard.modelData.name)
                  canvas.workspaceMoved(number, output)
              }
              onCanceled: { canvas.dragNumber = -1; canvas.dropOutput = "" }
            }
          }
        }
        Repeater {
          model: monitorCard.step.shown ? [{ glyph: "-", delta: -1, ready: monitorCard.step.down },
            { glyph: "+", delta: 1, ready: monitorCard.step.up }] : []
          delegate: Ui.BorderSurface {
            required property var modelData
            objectName: "workspaceStep-" + monitorCard.modelData.name + (modelData.delta < 0 ? "-down" : "-up")
            width: Style.space(20)
            height: Style.space(20)
            color: Commons.Color.popups.background
            borderSpec: Border.flat(Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent).color,
              Math.max(1, Style.normalBorderWidth))
            radius: Style.cornerRadius
            opacity: modelData.ready ? 1 : (canvas.tokens ? canvas.tokens.disabledOpacity : 0.5)
            Text {
              anchors.centerIn: parent
              text: parent.modelData.glyph
              color: Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              anchors.fill: parent
              enabled: parent.modelData.ready
              cursorShape: Qt.PointingHandCursor
              onClicked: canvas.countChangeRequested(monitorCard.modelData.name, parent.modelData.delta)
            }
          }
        }
      }

      Row {
        x: 0; y: -height - Style.spacing.sm
        spacing: Style.spacing.sm
        Text {
          objectName: "workspaceMonitorName-" + monitorCard.modelData.name
          text: monitorCard.modelData.name
          textFormat: Text.PlainText
          color: canvas.tokens ? canvas.tokens.textDim : Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          objectName: "workspaceMonitorRole-" + monitorCard.modelData.name
          text: monitorCard.outputIndex !== -1 ? "| " + (monitorCard.outputIndex + 1) : "| Off"
          color: canvas.tokens ? canvas.tokens.textDim : Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

    }
  }

  // The dragged badge follows the pointer.
  Ui.BorderSurface {
    objectName: "workspaceDragGhost"
    visible: canvas.dragNumber !== -1
    width: Math.max(Style.space(20), ghostLabel.implicitWidth + Style.space(8))
    height: Style.space(20)
    x: canvas.dragX - width / 2
    y: canvas.dragY - height / 2
    color: Commons.Color.menu.selectedBackground
    borderSpec: Border.flat(Commons.Color.accent, Math.max(1, Style.normalBorderWidth))
    radius: Style.cornerRadius
    Text {
      id: ghostLabel
      anchors.centerIn: parent
      text: String(canvas.dragNumber)
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
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
