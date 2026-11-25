import QtQuick
import "../panel" as PanelUi
import qs.Commons
import qs.Commons as Commons

PanelUi.MonitorCanvas {
  id: canvas
  required tokens
  required service
  property string selectedDisplayName: ""
  property bool narrow: false
  signal displaySelected(string name)
  readonly property real barEdgeGap: Style.spacing.sm
  // Applying a bar's on/off state builds or destroys its layer surface on this thread,
  // which would freeze the switch mid-throw. The switch moves first, then this applies.
  property string pendingBarName: ""
  property bool pendingBarEnabled: false
  property string barToggleError: ""

  function requestBarEnabled(name, enabled) {
    if (pendingBarName && pendingBarName !== name) applyPendingBar()
    pendingBarName = name
    pendingBarEnabled = enabled
    barToggleApply.restart()
  }

  function applyPendingBar() {
    barToggleApply.stop()
    if (!pendingBarName) return
    var result = service ? service.setMonitorBarEnabled(pendingBarName, pendingBarEnabled) : undefined
    barToggleError = result === "last-bar"
      ? "At least one bar must stay on. Turn on another bar first." : ""
    // Cleared last, so a refused change is what moves the switch back.
    pendingBarName = ""
  }

  Timer {
    id: barToggleApply
    interval: Style.duration(160)
    onTriggered: canvas.applyPendingBar()
  }
  // Closing the panel right after a click must not lose the change.
  Component.onDestruction: applyPendingBar()

  Repeater {
    model: canvas.displays
    delegate: PanelUi.MonitorCard {
      id: monitorCard
      layout: canvas
      isSelected: canvas.selectedDisplayName === modelData.name
      outputEnabled: canvas.service
        ? canvas.service.displayEnabled(modelData.name) : modelData.enabled
      readonly property var barSetting: canvas.service
        ? canvas.service.monitorBar(modelData.name)
        : ({ enabled: true, position: "top", width: 100, height: 0, background: "solid", style: "default", contentSize: 0 })
      readonly property bool barEnabled: canvas.pendingBarName === modelData.name
        ? canvas.pendingBarEnabled : barSetting.enabled === true
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

      Column {
        id: monitorIdentity
        objectName: "barMonitorIdentity-" + monitorCard.modelData.name
        anchors.centerIn: parent
        spacing: Style.spacing.xs
        z: 3

        PanelUi.MonitorName {
          id: monitorName
          centerInParent: false
          name: monitorCard.modelData.name
          width: Math.min(implicitWidth, monitorCard.width - Style.spacing.sm * 2)
          x: (parent.width - width) / 2
        }

        PanelUi.ToggleSwitch {
          id: barEnabledSwitch
          objectName: "barEnabledSwitch"
          trackWidth: Style.space(32)
          trackHeight: Style.space(18)
          knobSize: Style.space(14)
          sizeFactor: canvas.narrow ? 0.7 : 1
          x: (parent.width - width) / 2
          checked: monitorCard.barEnabled
          onToggled: {
            canvas.displaySelected(monitorCard.modelData.name)
            canvas.requestBarEnabled(monitorCard.modelData.name, !checked)
          }
        }
      }

      Rectangle {
        id: barPreview
        objectName: "barPreview-" + monitorCard.modelData.name
        visible: monitorCard.barEnabled
        color: monitorCard.barSetting.style === "pill" ? "transparent" : Commons.Color.accent
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
            color: Commons.Color.accent
            radius: Math.min(width, height) / 2
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: canvas.displaySelected(monitorCard.modelData.name)
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
            color: monitorCard.barEnabled
              && monitorCard.barSetting.position === parent.modelData.position
              ? Commons.Color.accent : Commons.Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              canvas.displaySelected(monitorCard.modelData.name)
              canvas.service.setMonitorBarPosition(monitorCard.modelData.name, parent.modelData.position)
            }
          }
        }
      }

    }
  }
}
