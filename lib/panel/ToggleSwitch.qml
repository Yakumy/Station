import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

// Both pieces follow the live Windows roundness setting through the host token.
Item {
  id: root
  property bool checked: false
  property bool busy: false
  property bool interactive: true
  property color foreground: Qt.darker(Commons.Color.popups.text, 1.4)
  property color accent: Commons.Color.accent
  readonly property bool mirrored: LayoutMirroring.enabled
  readonly property bool containsMouse: mouse.containsMouse
  property int trackHeight: Style.space(24)
  property int trackWidth: Style.space(44)
  property int knobSize: Style.space(20)
  property int knobInset: Style.space(2)
  // Bar portrait draws every switch at 70%; the base sizes stay the reference.
  property real sizeFactor: 1
  readonly property real drawnTrackWidth: Math.round(trackWidth * sizeFactor)
  readonly property real drawnTrackHeight: Math.round(trackHeight * sizeFactor)
  readonly property real drawnKnobSize: Math.round(knobSize * sizeFactor)
  readonly property real drawnKnobInset: Math.max(1, Math.round(knobInset * sizeFactor))
  signal toggled()
  signal hovered(bool isHovered)
  implicitWidth: drawnTrackWidth
  implicitHeight: drawnTrackHeight

  Ui.BorderSurface {
    objectName: "switchTrack"
    width: root.drawnTrackWidth; height: root.drawnTrackHeight
    anchors.centerIn: parent
    radius: Style.cornerRadius
    color: root.checked ? Style.selectedAccentFill
      : Style.normalFillFor(root.foreground, root.accent)
    borderSpec: root.checked ? Border.flat(root.accent, Style.normalBorderWidth)
      : Border.controlSpec("normal", root.foreground, root.accent)
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Rectangle {
      objectName: "switchKnob"
      width: root.drawnKnobSize; height: root.drawnKnobSize
      radius: Style.cornerRadius
      x: root.checked !== root.mirrored ? parent.width - width - root.drawnKnobInset : root.drawnKnobInset
      anchors.verticalCenter: parent.verticalCenter
      color: root.checked ? root.accent : root.foreground
      Behavior on x { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: if (!root.busy) root.toggled()
  }
}
