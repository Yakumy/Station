import QtQuick
import qs.Ui as Ui
import qs.Commons
import "Wallpaper.js" as Wallpaper
import "." as Station

Ui.BorderSurface {
  id: root
  required property var controller
  property string selectedName: ""
  signal selected(string name)
  readonly property var layout: controller.layout
  readonly property var scene: controller.draft
  readonly property bool spanning: scene.mode === "span"
  readonly property real inset: Style.space(16)
  readonly property real imageFit: Math.min((width - inset * 2) / Math.max(1, background.sourceSize.width),
    (height - inset * 2) / Math.max(1, background.sourceSize.height))
  readonly property var crop: Wallpaper.composition(layout, background.sourceSize.width, background.sourceSize.height, scene.framing)
  readonly property real fit: spanning ? crop.unit * imageFit
    : Math.min((width - inset * 2) / layout.width, (height - inset * 2) / layout.height)
  readonly property real groupX: spanning ? background.x + crop.x * imageFit : (width - layout.width * fit) / 2
  readonly property real groupY: spanning ? background.y + crop.y * imageFit : (height - layout.height * fit) / 2
  readonly property size sourceSize: background.sourceSize
  color: Color.popups.background
  borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
  radius: Style.cornerRadius
  clip: true
  activeFocusOnTab: true
  function zoom(factor) {
    if (!spanning) return
    controller.frame(Object.assign({}, scene.framing, { zoom: scene.framing.zoom * factor }))
  }
  function nudge(dx, dy) {
    controller.frame(Object.assign({}, scene.framing,
      { x: scene.framing.x + dx, y: scene.framing.y + dy }))
  }
  Keys.onLeftPressed: if (spanning) nudge(-0.02, 0)
  Keys.onRightPressed: if (spanning) nudge(0.02, 0)
  Keys.onUpPressed: if (spanning) nudge(0, -0.02)
  Keys.onDownPressed: if (spanning) nudge(0, 0.02)
  Image {
    id: background
    source: Util.fileUrl(root.scene.source)
    asynchronous: true
    width: sourceSize.width * root.imageFit
    height: sourceSize.height * root.imageFit
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    visible: root.spanning
    fillMode: Image.PreserveAspectFit
  }
  Repeater {
    model: root.layout.displays
    delegate: Item {
      id: monitor
      required property var modelData
      x: root.groupX + modelData.x * root.fit
      y: root.groupY + modelData.y * root.fit
      width: modelData.width * root.fit
      height: modelData.height * root.fit
      Station.WallpaperImage {
        anchors.fill: parent
        visible: !root.spanning
        scene: root.scene
        layout: root.layout
        display: monitor.modelData
      }
      Ui.BorderSurface {
        anchors.fill: parent
        color: "transparent"
        borderSpec: root.spanning || root.selectedName === monitor.modelData.name
          ? Border.flat(Color.accent, Style.normalBorderWidth * 2)
          : Border.controlSpec("normal", Color.popups.text, Color.accent)
        radius: Style.cornerRadius
      }
      Rectangle {
        anchors.centerIn: parent
        width: label.implicitWidth + Style.space(12)
        height: label.implicitHeight + Style.space(8)
        color: Color.popups.background
        radius: Style.cornerRadius
        Text {
          id: label
          anchors.centerIn: parent
          text: monitor.modelData.name
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: !root.spanning
        cursorShape: Qt.PointingHandCursor
        onClicked: root.selected(monitor.modelData.name)
      }
    }
  }
  MouseArea {
    anchors.fill: parent
    enabled: root.spanning && !root.controller.busy
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real startX: 0
    property real startY: 0
    property var startFrame
    onPressed: function(mouse) {
      root.forceActiveFocus()
      startX = mouse.x; startY = mouse.y; startFrame = Object.assign({}, root.scene.framing)
    }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      var slackX = background.width - root.layout.width * root.fit
      var slackY = background.height - root.layout.height * root.fit
      root.controller.frame({ zoom: startFrame.zoom,
        x: slackX > 0 ? startFrame.x + (mouse.x - startX) / slackX : 0.5,
        y: slackY > 0 ? startFrame.y + (mouse.y - startY) / slackY : 0.5 })
    }
    onWheel: function(wheel) { root.zoom(wheel.angleDelta.y > 0 ? 1.1 : 1 / 1.1); wheel.accepted = true }
  }
  Text {
    visible: !root.layout.displays.length
    anchors.centerIn: parent
    text: "No active displays"
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
}
