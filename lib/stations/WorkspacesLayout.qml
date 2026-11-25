import QtQuick
import "../panel" as PanelUi
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Monitor layout for the Workspaces tab. Positions follow Displays and cannot be
// dragged or selected here. Each managed output shows its role and the workspaces
// the draft gives it. Repetitive has − and + on every monitor, Non-repetitive on
// the last one, and Non-repetitive badges drag onto another monitor.
PanelUi.MonitorCanvas {
  id: canvas
  objectName: "workspacesLayout"
  // Cards never move here; only their badges and − and + take input.
  zoomable: true
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

  Repeater {
    id: monitorCards
    model: canvas.displays
    delegate: PanelUi.MonitorCard {
      id: monitorCard
      layout: canvas
      objectName: "workspaceMonitor-" + modelData.name
      readonly property int outputIndex: canvas.outputs.indexOf(modelData.name)
      readonly property var numbers: outputIndex !== -1 ? canvas.assigned[outputIndex] || [] : []
      readonly property var step: outputIndex !== -1 && canvas.steps[outputIndex] ? canvas.steps[outputIndex]
        : ({ shown: false, down: false, up: false })
      readonly property bool dropTarget: canvas.dragNumber !== -1 && canvas.dropOutput === modelData.name
      outline: dropTarget ? Commons.Color.accent
        : Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent).color
      outputEnabled: outputIndex !== -1

      Row {
        id: monitorIdentity
        objectName: "workspaceMonitorIdentity-" + monitorCard.modelData.name
        anchors.centerIn: parent
        // Cards sit at zoomed, fractional geometry, so pixel snapping only offsets the row.
        anchors.alignWhenCentered: false
        spacing: Style.spacing.sm
        z: 2

        PanelUi.MonitorName {
          id: monitorName
          centerInParent: false
          name: monitorCard.modelData.name
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          objectName: "workspaceMonitorSeparator-" + monitorCard.modelData.name
          text: "|"
          textFormat: Text.PlainText
          color: monitorName.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          objectName: "workspaceMonitorRole-" + monitorCard.modelData.name
          text: monitorCard.outputIndex === -1 ? "Off" : String(monitorCard.outputIndex + 1)
          textFormat: Text.PlainText
          color: monitorName.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Flow {
        objectName: "workspaceBadges-" + monitorCard.modelData.name
        x: Style.spacing.sm
        y: Style.spacing.sm
        width: Math.max(0, parent.width - Style.spacing.sm * 2)
        height: Math.max(0, (parent.height - Style.font.caption) / 2 - Style.spacing.sm * 2)
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
}
