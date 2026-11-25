import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model
import "../panel" as PanelUi

PanelUi.MonitorCanvas {
  id: canvas
  zoomable: true
  property string selectedDisplayName: ""
  signal displaySelected(string name)
  height: Style.space(370)

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
    if (service.setDisplayTransform(display.name, next) === "ok") service.previewLayout()
  }

  Repeater {
    id: monitorRepeater
    model: canvas.displays
    delegate: PanelUi.MonitorCard {
      id: monitorCard
      layout: canvas
      isSelected: canvas.selectedDisplayName === modelData.name
      outputEnabled: canvas.service ? canvas.service.displayEnabled(modelData.name) : modelData.enabled
      z: pointer.pressed ? 2 : (isSelected ? 1 : 0)
      Row {
        id: monitorIdentity
        objectName: "monitorIdentity-" + monitorCard.modelData.name
        anchors.centerIn: parent
        spacing: Style.spacing.sm
        z: 3
        PanelUi.MonitorName {
          id: monitorName
          centerInParent: false
          name: monitorCard.modelData.name
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          objectName: "monitorRoleSeparator-" + monitorCard.modelData.name
          text: "|"
          textFormat: Text.PlainText
          color: monitorName.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        PanelUi.InlineDropdown {
          id: roleMenu
          objectName: "monitorRoleMenu"
          visible: canvas.service
          enabled: canvas.service && canvas.service.draftEditable
          fontSize: Style.font.caption
          foreground: monitorName.foreground
          anchors.verticalCenter: parent.verticalCenter
          value: !monitorCard.outputEnabled ? "off"
            : (canvas.service ? String(canvas.service.roleOf(monitorCard.modelData.name)) : "")
          options: {
            if (!canvas.service) return []
            if (!monitorCard.outputEnabled)
              return [{ value: "off", label: "Off" }, { value: "on", label: "Enable" }]
            var count = canvas.displays.filter(function(display) { return canvas.service.displayEnabled(display.name) }).length
            var roles = []
            for (var index = 0; index < count; index++) roles.push({ value: String(index), label: String(index + 1) })
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
          property color iconColor: Commons.Color.popups.text
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
}
