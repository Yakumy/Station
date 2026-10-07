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
  readonly property real inset: canvas.panelRoot ? canvas.panelRoot.space4 : Style.spacing.md
  readonly property color cardBackground: Color.popups.background
  readonly property var displays: service ? service.displayDraft : []
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
  // Reserve room for both horizontal and vertical arrangements. Keep this
  // transform unchanged throughout a gesture by committing only on release.
  readonly property real fitZoom: Math.max(0.001, Math.min(0.06,
    (width - 2 * inset) * 0.85 / Math.max(bounds.width, bounds.sumWidth),
    (height - 2 * inset) * 0.85 / Math.max(bounds.height, bounds.sumHeight)))
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
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      readonly property bool isSelected: canvas.selectedDisplayName === modelData.name
      property real offsetX: 0
      property real offsetY: 0
      x: canvas.originX + canvas.panX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom + offsetX
      y: canvas.originY + canvas.panY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom + offsetY
      width: logicalSize.width * canvas.zoom
      height: logicalSize.height * canvas.zoom
      z: pointer.pressed ? 2 : (isSelected ? 1 : 0)
      color: monitorCard.isSelected ? Color.menu.selectedBackground : canvas.cardBackground
      borderSpec: Border.flat(isSelected
        ? Color.accent
        : Border.controlSpec("normal", Color.popups.text, Color.accent).color,
        isSelected ? Math.max(2, Style.normalBorderWidth) : Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius
      opacity: modelData.enabled || !canvas.panelRoot ? 1 : canvas.panelRoot.disabledOpacity
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
          visible: canvas.service
          enabled: canvas.service && canvas.service.state === "idle"
          prefix: "| "
          fontSize: Style.font.body
          value: !monitorCard.modelData.enabled ? "off"
            : (canvas.service ? String(canvas.service.roleOf(monitorCard.modelData.name)) : "")
          options: {
            if (!canvas.service) return []
            if (!monitorCard.modelData.enabled)
              return [{ value: "off", label: "Off" }, { value: "on", label: "Enable" }]
            var count = canvas.displays.filter(function(display) { return display.enabled }).length
            var roles = [1, 2, 3].slice(0, count).map(function(role, index) {
              return { value: String(index), label: String(role) }
            })
            if (count > 1) roles.push({ value: "off", label: "Turn off" })
            return roles
          }
          onChanged: function(value) {
            if (!canvas.service || canvas.service.state !== "idle") return
            if (value === "on" || value === "off") {
              if (canvas.service.setDisplayValue(monitorCard.modelData.name, "enabled", value === "on") === "ok")
                canvas.service.previewLayout()
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
      Repeater {
        model: [{ label: "↶", delta: -1, right: false }, { label: "↷", delta: 1, right: true }]
        delegate: Ui.BorderSurface {
          id: rotationHandle
          required property var modelData
          anchors.top: parent.top
          anchors.topMargin: canvas.panelRoot ? canvas.panelRoot.space1 : Style.spacing.xs
          anchors.left: modelData.right ? undefined : parent.left
          anchors.right: modelData.right ? parent.right : undefined
          anchors.leftMargin: canvas.panelRoot ? canvas.panelRoot.space1 : Style.spacing.xs
          anchors.rightMargin: canvas.panelRoot ? canvas.panelRoot.space1 : Style.spacing.xs
          width: Style.space(20)
          height: Style.space(20)
          visible: monitorCard.isSelected
          opacity: rotationPointer.containsMouse ? 1 : 0
          color: canvas.cardBackground
          borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
          radius: Style.cornerRadius
          z: 3
          Text {
            anchors.centerIn: parent
            text: rotationHandle.modelData.label
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            id: rotationPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: canvas.rotateDisplay(monitorCard.modelData, rotationHandle.modelData.delta)
          }
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
      model: [{ glyph: "󰍴", factor: 1 / 1.2 }, { glyph: "󰍶", factor: 1.2 }]
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
