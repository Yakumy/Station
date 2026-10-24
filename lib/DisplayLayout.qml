import QtQuick
import QtQuick.Controls
import qs.Ui as Ui
import qs.Commons
import "Model.js" as Model
import "." as Station

Ui.BorderSurface {
  id: canvas
  property var service: null
  property var panelRoot: null
  property string selectedDisplayName: ""
  signal displaySelected(string name)
  height: Style.space(370)
  clip: true
  color: Color.popups.background
  borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
  radius: Style.cornerRadius
  // The dotted grid and the drag snap are the same 16px step, so what you see
  // is what you land on.
  readonly property real gridStep: Style.space(16)
  readonly property real monitorGap: Style.spacing.sm
  readonly property real horizontalInset: width * 0.1
  readonly property real verticalInset: height * 0.1
  readonly property color cardBackground: Color.popups.background
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
  // Default framing keeps about ten percent clear on every canvas edge. Keep
  // this transform unchanged throughout a gesture by committing only on release.
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

  function commitPosition(display, x, y) {
    if (!service || !service.draftEditable) return
    var snapped = Model.snapPosition(display, x, y, displays, gridStep / zoom)
    // This function belongs to the canvas, which survives rebuilding the
    // Repeater. Never continue a service mutation from a destroyed delegate.
    if (service.setDisplayPosition(display.name, snapped.x, snapped.y) === "ok") service.previewLayout()
  }

  function rotateDisplay(display, delta) {
    if (!service || !service.draftEditable) return
    var transform = Number(display.transform) || 0
    var flipped = transform >= 4 ? 4 : 0
    var next = flipped + ((transform - flipped + delta + 4) % 4)
    if (service.setDisplayValue(display.name, "transform", next) === "ok") service.previewLayout()
  }

  Canvas {
    id: dotGrid
    anchors.fill: parent
    opacity: 0.22
    property color dotColor: Color.popups.text
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

  MouseArea {
    id: backgroundPointer
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
    id: monitorRepeater
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      readonly property bool isSelected: canvas.selectedDisplayName === modelData.name
      readonly property bool outputEnabled: canvas.service ? canvas.service.displayEnabled(modelData.name) : modelData.enabled
      property real offsetX: 0
      property real offsetY: 0
      x: canvas.originX + canvas.panX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom
        + canvas.monitorGap / 2 + offsetX
      y: canvas.originY + canvas.panY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom
        + canvas.monitorGap / 2 + offsetY
      width: Math.max(1, logicalSize.width * canvas.zoom - canvas.monitorGap)
      height: Math.max(1, logicalSize.height * canvas.zoom - canvas.monitorGap)
      z: pointer.pressed ? 2 : (isSelected ? 1 : 0)
      color: monitorCard.isSelected ? Color.menu.selectedBackground : canvas.cardBackground
      borderSpec: Border.flat(isSelected
        ? Color.accent
        : Border.controlSpec("normal", Color.popups.text, Color.accent).color,
        isSelected ? Math.max(2, Style.normalBorderWidth) : Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius
      opacity: outputEnabled || !canvas.panelRoot ? 1 : canvas.panelRoot.disabledOpacity
      Row {
        anchors.centerIn: parent
        spacing: Style.spacing.sm
        z: 3
        Text {
          text: monitorCard.modelData.name
          color: monitorCard.isSelected || !canvas.panelRoot
            ? Color.popups.text : canvas.panelRoot.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Station.InlineDropdown {
          id: roleMenu
          objectName: "monitorRoleMenu"
          visible: canvas.service
          enabled: canvas.service && canvas.service.draftEditable
          prefix: "| "
          fontSize: Style.font.body
          value: !monitorCard.outputEnabled ? "off"
            : (canvas.service ? String(canvas.service.roleOf(monitorCard.modelData.name)) : "")
          options: {
            if (!canvas.service) return []
            if (!monitorCard.outputEnabled)
              return [{ value: "off", label: "Off" }, { value: "on", label: "Enable" }]
            var count = canvas.displays.filter(function(display) { return canvas.service.displayEnabled(display.name) }).length
            var roles = [1, 2, 3].slice(0, count).map(function(role, index) {
              return { value: String(index), label: String(role) }
            })
            if (canvas.service.state !== "idle") roles = roles.filter(function(role) { return role.value === roleMenu.value })
            if (count > 1) roles.push({ value: "off", label: "Turn off" })
            return roles
          }
          onChanged: function(value) {
            if (!canvas.service || !canvas.service.draftEditable) return
            if (value === "on" || value === "off") {
              // The service owns the entire edit: publishing displayDraft
              // destroys this delegate synchronously.
              canvas.service.setDisplayEnabled(monitorCard.modelData.name, value === "on")
            } else if (canvas.service.state === "idle") {
              canvas.service.swapRole(monitorCard.modelData.name, Number(value))
            }
          }
        }
      }
      MouseArea {
        id: pointer
        anchors.fill: parent
        z: 1
        enabled: canvas.service && canvas.service.draftEditable
        // Retain the gesture if this component is ever embedded in a Flickable.
        preventStealing: true
        property point startPointer
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: function(mouse) {
          startPointer = mapToItem(canvas, mouse.x, mouse.y)
          canvas.displaySelected(modelData.name)
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var position = mapToItem(canvas, mouse.x, mouse.y)
          monitorCard.offsetX = position.x - startPointer.x
          monitorCard.offsetY = position.y - startPointer.y
        }
        onCanceled: { monitorCard.offsetX = 0; monitorCard.offsetY = 0 }
        onReleased: {
          var dx = monitorCard.offsetX, dy = monitorCard.offsetY
          var display = modelData
          monitorCard.offsetX = 0; monitorCard.offsetY = 0
          if (Math.hypot(dx, dy) < Qt.styleHints.startDragDistance) return
          canvas.commitPosition(display, Number(display.x) + dx / canvas.zoom, Number(display.y) + dy / canvas.zoom)
        }
        onWheel: function(wheel) {
          var point = mapToItem(canvas, wheel.x, wheel.y)
          canvas.zoomAt(wheel.angleDelta.y > 0 ? 1.15 : 1 / 1.15, point.x, point.y)
          wheel.accepted = true
        }
      }
    }
  }

  // Controls must be siblings of the cards: QML does not deliver pointer
  // events to a card's children outside that card's bounds.
  Item {
    id: rotationTools
    objectName: "rotationTools"
    readonly property var selectedCard: {
      for (var i = 0; i < monitorRepeater.count; i++) {
        var card = monitorRepeater.itemAt(i)
        if (card && card.modelData.name === canvas.selectedDisplayName) return card
      }
      return null
    }
    readonly property real handleSize: Style.space(32)
    readonly property real cornerReach: Style.space(30)
    readonly property real gap: Style.spacing.sm * 0.6
    readonly property real outerExtent: handleSize + gap
    readonly property real reachX: Math.min(cornerReach, selectedCard ? selectedCard.width / 2 : cornerReach)
    readonly property real reachY: Math.min(cornerReach, selectedCard ? selectedCard.height / 2 : cornerReach)
    width: selectedCard ? selectedCard.width + outerExtent * 2 : 0
    height: selectedCard ? selectedCard.height + outerExtent * 2 : 0
    x: selectedCard ? selectedCard.x - outerExtent : 0
    y: selectedCard ? selectedCard.y - outerExtent : 0
    visible: selectedCard !== null
    z: 4
    Repeater {
      model: [
        { delta: -1, right: false, bottom: false, name: "rotateTopLeft" },
        { delta: 1, right: true, bottom: false, name: "rotateTopRight" },
        { delta: -1, right: false, bottom: true, name: "rotateBottomLeft" },
        { delta: 1, right: true, bottom: true, name: "rotateBottomRight" }
      ]
      delegate: Item {
        id: rotationHandle
        required property var modelData
        objectName: modelData.name
        anchors.left: modelData.right ? undefined : parent.left
        anchors.right: modelData.right ? parent.right : undefined
        anchors.top: modelData.bottom ? undefined : parent.top
        anchors.bottom: modelData.bottom ? parent.bottom : undefined
        width: rotationTools.outerExtent + rotationTools.reachX
        height: rotationTools.outerExtent + rotationTools.reachY
        Canvas {
          objectName: "rotationIcon"
          anchors.left: rotationHandle.modelData.right ? undefined : parent.left
          anchors.right: rotationHandle.modelData.right ? parent.right : undefined
          anchors.top: rotationHandle.modelData.bottom ? undefined : parent.top
          anchors.bottom: rotationHandle.modelData.bottom ? parent.bottom : undefined
          width: rotationTools.handleSize
          height: rotationTools.handleSize
          visible: rotationPointer.containsMouse
          property color iconColor: Color.popups.text
          readonly property real artworkScale: 0.7
          onIconColorChanged: requestPaint()
          onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)
            context.save()
            // Face the arc's open side toward this monitor corner.
            if (rotationHandle.modelData.right) {
              context.translate(width, 0)
              context.scale(-1, 1)
            }
            if (rotationHandle.modelData.bottom) {
              context.translate(0, height)
              context.scale(1, -1)
            }
            // Shrink the artwork while keeping its closest edges to the card fixed.
            context.translate(width * 0.84 * (1 - artworkScale), height * 0.84 * (1 - artworkScale))
            context.scale(artworkScale, artworkScale)
            context.strokeStyle = iconColor
            context.fillStyle = iconColor
            context.lineWidth = Math.max(2, Style.normalBorderWidth)
            context.lineCap = "round"
            context.lineJoin = "round"
            // A curved stem with an arrowhead at each end, as in the rotate cursor.
            context.beginPath()
            context.moveTo(width * 0.28, height * 0.72)
            context.lineTo(width * 0.28, height * 0.55)
            context.quadraticCurveTo(width * 0.28, height * 0.27, width * 0.57, height * 0.27)
            context.lineTo(width * 0.76, height * 0.27)
            context.stroke()
            context.beginPath()
            context.moveTo(width * 0.14, height * 0.67)
            context.lineTo(width * 0.28, height * 0.84)
            context.lineTo(width * 0.42, height * 0.67)
            context.closePath()
            context.fill()
            context.beginPath()
            context.moveTo(width * 0.66, height * 0.13)
            context.lineTo(width * 0.84, height * 0.27)
            context.lineTo(width * 0.66, height * 0.41)
            context.closePath()
            context.fill()
            context.restore()
          }
        }
        MouseArea {
          id: rotationPointer
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: canvas.rotateDisplay(rotationTools.selectedCard.modelData, rotationHandle.modelData.delta)
        }
      }
    }
  }

  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.sm
    z: 5
    Repeater {
      model: [{ glyph: "-", factor: 1 / 1.2 }, { glyph: "+", factor: 1.2 }]
      delegate: Item {
        required property var modelData
        width: Style.space(23)
        height: Style.space(23)
        Text {
          anchors.centerIn: parent
          text: modelData.glyph
          color: Qt.darker(Color.popups.text, 1.4)
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
