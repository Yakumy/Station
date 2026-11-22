import QtQuick
import qs.Commons
import qs.Commons as Commons
import "ScrollHint.js" as ScrollHint

// A thin accent scroll thumb for an overflowing Flickable, shared by the dropdown
// menus and the Workspaces control frame. Place it in the Flickable's parent, above it.
//
// The line shows only while the pointer is on the thumb or drags it. A grab strip
// wider than the line covers the thumb's span and takes the press, so the rows or
// options under it never see it, and dragging moves the list with the pointer.
// The thumb travels the middle 80% of the list, so its rounded ends stay clear of
// the container's rounded corners.
Item {
  id: root
  required property Flickable flickable
  property color color: Commons.Color.accent

  // Thumbs that share a key play the scroll hint once per shell session between
  // them; an empty key never plays it.
  property string hintKey: ""
  // Omarchy's motion toggle; a thumb can be given its own value.
  property bool reduceMotion: Style.reduceMotion

  readonly property real track: flickable.height * 0.8
  readonly property real trackTop: flickable.y + flickable.height * 0.1
  readonly property bool shown: grab.containsMouse || grab.pressed || hint.running
  readonly property bool onScreen: visible && Window.window !== null && Window.window.visible

  // The first time an overflowing list appears, it scrolls a little and back, with
  // the thumb shown, so the user sees that it scrolls. A short wait lets a popup or
  // tab finish arriving first. Reduced motion skips it without using up the key.
  onOnScreenChanged: if (onScreen && hintKey !== "") hintDelay.restart()
  Timer {
    id: hintDelay
    interval: 300
    onTriggered: root.playHint()
  }
  function playHint() {
    var list = flickable
    if (!onScreen || reduceMotion || grab.pressed || list.moving || hint.running) return
    var top = list.originY, bottom = list.originY + list.contentHeight - list.height
    if (bottom <= top || !ScrollHint.claim(hintKey)) return
    // Peek down, or up when the list already rests at its end.
    var distance = Math.min(bottom - top, list.height * 0.35)
    var from = list.contentY
    hintOut.from = from
    hintOut.to = list.contentY < bottom - 1 ? Math.min(bottom, from + distance) : Math.max(top, from - distance)
    hintBack.from = hintOut.to
    hintBack.to = from
    hint.start()
  }
  SequentialAnimation {
    id: hint
    NumberAnimation { id: hintOut; target: root.flickable; property: "contentY"; duration: 280; easing.type: Easing.OutCubic }
    PauseAnimation { duration: 140 }
    NumberAnimation { id: hintBack; target: root.flickable; property: "contentY"; duration: 360; easing.type: Easing.InOutCubic }
  }
  // The user takes over: stop the hint where it is.
  Connections {
    target: root.flickable
    function onDraggingChanged() { if (root.flickable.dragging) hint.stop() }
    function onFlickingChanged() { if (root.flickable.flicking) hint.stop() }
  }

  z: 2
  visible: flickable.contentHeight > flickable.height
  anchors.right: parent.right
  width: Style.space(6)
  height: Math.max(Style.space(2), track * flickable.visibleArea.heightRatio)
  y: trackTop + Math.max(0, Math.min(track - height, track * flickable.visibleArea.yPosition))

  MouseArea {
    id: grab
    objectName: "scrollThumbGrab"
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true
    property real startY: 0
    property real startContentY: 0

    // Parent coordinates: the thumb itself moves while it is dragged.
    function pointerY(mouse) { return mapToItem(root.parent, mouse.x, mouse.y).y }

    onPressed: function(mouse) {
      hint.stop()
      startY = pointerY(mouse)
      startContentY = root.flickable.contentY
    }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      var list = root.flickable
      // One pixel of thumb travel covers contentHeight / track pixels of content.
      var next = startContentY + (pointerY(mouse) - startY) * list.contentHeight / Math.max(1, root.track)
      list.contentY = Math.max(list.originY, Math.min(list.originY + list.contentHeight - list.height, next))
    }
  }

  Rectangle {
    objectName: "scrollThumbLine"
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.hairline
    width: Style.space(1)
    height: parent.height
    radius: Style.cornerRadius
    color: root.color
    opacity: root.shown ? 0.9 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(100) } }
  }
}
