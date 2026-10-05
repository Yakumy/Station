import QtQuick
import qs.Ui as Ui
import qs.Commons
import "Model.js" as Model

Ui.BorderSurface {
  id: canvas
  property var service: null
  property var panelRoot: null
  property string selectedDisplayName: ""
  signal displaySelected(string name)
  height: Style.space(190)
  color: Color.popups.background
  borderSpec: Border.flat(canvas.panelRoot ? canvas.panelRoot.hairline : Color.popups.border,
    Math.max(1, Style.normalBorderWidth))
  radius: canvas.panelRoot ? canvas.panelRoot.radiusMd : Style.cornerRadius
  // The dotted grid and the drag snap are the same 16px step, so what you see
  // is what you land on.
  readonly property real gridStep: Style.space(16)
  readonly property real inset: canvas.panelRoot ? canvas.panelRoot.space4 : Style.spacing.md
  readonly property color cardBackground: Color.popups.background
  readonly property color cardOutline: Color.popups.text
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
  readonly property real zoom: Math.max(0.001, Math.min(0.06,
    (width - 2 * inset) * 0.85 / Math.max(bounds.width, bounds.sumWidth),
    (height - 2 * inset) * 0.85 / Math.max(bounds.height, bounds.sumHeight)))
  readonly property real originX: (width - bounds.width * zoom) / 2
  readonly property real originY: (height - bounds.height * zoom) / 2

  function commitPosition(display, x, y) {
    if (!service || service.state !== "idle") return
    var snapped = Model.snapPosition(display, x, y, displays, gridStep / zoom)
    // This function belongs to the canvas, which survives rebuilding the
    // Repeater. Never continue a service mutation from a destroyed delegate.
    if (service.setDisplayPosition(display.name, snapped.x, snapped.y) === "ok") service.previewLayout()
  }

  function rotateDisplay(display, delta) {
    if (!service || service.state !== "idle") return
    var transform = Number(display.transform) || 0
    var flipped = transform >= 4 ? 4 : 0
    var next = flipped + ((transform - flipped + delta + 4) % 4)
    if (service.setDisplayValue(display.name, "transform", next) === "ok") service.previewLayout()
  }

  Canvas {
    id: dotGrid
    anchors.fill: parent
    opacity: 0.22
    property color dotColor: Color.popups.border
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

  Repeater {
    model: canvas.displays
    delegate: Ui.BorderSurface {
      id: monitorCard
      required property var modelData
      readonly property var logicalSize: Model.logicalSize(modelData)
      readonly property bool isSelected: canvas.selectedDisplayName === modelData.name
      property real offsetX: 0
      property real offsetY: 0
      x: canvas.originX + (Number(modelData.x) - canvas.bounds.x) * canvas.zoom + offsetX
      y: canvas.originY + (Number(modelData.y) - canvas.bounds.y) * canvas.zoom + offsetY
      width: logicalSize.width * canvas.zoom
      height: logicalSize.height * canvas.zoom
      z: pointer.pressed ? 2 : (isSelected ? 1 : 0)
      // Menu selection can be transparent in a theme. Monitor cards must
      // cover the grid; selection is conveyed by the brighter outline.
      color: Qt.rgba(canvas.cardBackground.r, canvas.cardBackground.g, canvas.cardBackground.b, 1)
      // Selection is the one elevation cue in the system: a thicker accent
      // border plus a muted accent halo behind the card.
      borderSpec: Border.flat(isSelected
        ? Color.accent
        : Qt.rgba(canvas.cardOutline.r, canvas.cardOutline.g, canvas.cardOutline.b, 0.45),
        isSelected ? Math.max(2, Style.normalBorderWidth) : Math.max(1, Style.normalBorderWidth))
      radius: canvas.panelRoot ? canvas.panelRoot.radiusMd : Style.cornerRadius
      opacity: modelData.enabled ? 1 : 0.5
      Ui.BorderSurface {
        visible: monitorCard.isSelected && canvas.panelRoot !== null
        anchors.fill: parent
        anchors.margins: canvas.panelRoot ? -canvas.panelRoot.focusHalo : 0
        radius: monitorCard.radius + (canvas.panelRoot ? canvas.panelRoot.focusHalo : 0)
        color: "transparent"
        borderSpec: Border.flat(canvas.panelRoot ? canvas.panelRoot.accentMuted : "transparent",
          canvas.panelRoot ? canvas.panelRoot.focusHalo : 0)
        z: -1
      }
      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.xxs
        Text {
          text: monitorCard.modelData.enabled && canvas.service
            ? canvas.service.roleOf(monitorCard.modelData.name) + 1 : "Off"
          horizontalAlignment: Text.AlignHCenter
          color: canvas.panelRoot ? canvas.panelRoot.textPrimary : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
        Text {
          text: monitorCard.modelData.name
          horizontalAlignment: Text.AlignHCenter
          color: monitorCard.isSelected && canvas.panelRoot
            ? canvas.panelRoot.accentHover
            : (canvas.panelRoot ? canvas.panelRoot.textDim : Color.popups.text)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: canvas.service && canvas.service.state === "idle"
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
      }
      Row {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: canvas.panelRoot ? canvas.panelRoot.space1 : Style.spacing.xs
        spacing: canvas.panelRoot ? canvas.panelRoot.space1 : Style.spacing.xs
        z: 2
        Repeater {
          model: [{ label: "↶", delta: -1 }, { label: "↷", delta: 1 }]
          delegate: Ui.BorderSurface {
            required property var modelData
            width: Style.space(18)
            height: Style.space(18)
            color: canvas.cardBackground
            borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
            radius: canvas.panelRoot ? canvas.panelRoot.radiusSm : Style.cornerRadius
            Text {
              anchors.centerIn: parent
              text: modelData.label
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: canvas.rotateDisplay(monitorCard.modelData, modelData.delta)
            }
          }
        }
      }
    }
  }
}
