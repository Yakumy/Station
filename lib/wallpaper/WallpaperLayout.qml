import QtQuick
import qs.Ui as Ui
import qs.Commons
import "Wallpaper.js" as Wallpaper
import "." as WallpaperUi

Ui.BorderSurface {
  id: root
  required property var controller
  property string selectedName: ""
  signal selected(string name)
  readonly property var layout: controller.layout
  readonly property var scene: controller.draft
  // The panel reads the draft through a polled bridge, too slow to follow a pointer.
  // A gesture draws from this local frame and reaches the controller once it settles.
  property var liveFrame: null
  property bool liveCommitted: false
  readonly property var shownScene: liveFrame ? Wallpaper.withFrame(scene, liveFrame.identity, liveFrame.frame) : scene
  onSceneChanged: if (liveCommitted && liveSettled()) releaseFrame()
  readonly property bool spanning: scene.mode === "span"
  readonly property real horizontalInset: width * 0.1
  readonly property real verticalInset: Math.max(height * 0.1, Style.font.caption + Style.spacing.sm * 2)
  readonly property real gridStep: Style.space(16)
  readonly property real monitorGap: spanning ? 0 : Style.spacing.sm
  property size readySourceSize: Qt.size(1, 1)
  readonly property real layoutFit: Math.min(
    (width - horizontalInset * 2) / Math.max(1, layout.width),
    (height - verticalInset * 2) / Math.max(1, layout.height))
  readonly property real baseCropUnit: Math.max(0.001, Math.min(
    readySourceSize.width / Math.max(1, layout.width),
    readySourceSize.height / Math.max(1, layout.height)))
  // At the default zoom, fit the monitor union rather than the whole source
  // image. Wider/taller source context may extend beyond the clipped canvas.
  readonly property real imageFit: layoutFit / baseCropUnit
  readonly property var crop: Wallpaper.composition(layout, readySourceSize.width, readySourceSize.height, scene.framing)
  readonly property real fit: spanning ? crop.unit * imageFit
    : layoutFit
  readonly property real groupX: spanning ? background.x + crop.x * imageFit : (width - layout.width * fit) / 2
  readonly property real groupY: spanning ? background.y + crop.y * imageFit : (height - layout.height * fit) / 2
  readonly property size sourceSize: readySourceSize
  color: Color.popups.background
  borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
  radius: Style.cornerRadius
  clip: true
  activeFocusOnTab: true
  function zoom(factor) {
    if (!spanning) return
    controller.frame(Object.assign({}, scene.framing, { zoom: scene.framing.zoom * factor }))
  }
  function frameOf(display) { return Wallpaper.frameFor(shownScene, display) }
  function setFrame(display, value) {
    if (spanning || controller.busy) return
    if (liveFrame && liveFrame.identity !== display.identity) commitFrame()
    frameRelease.stop()
    liveCommitted = false
    liveFrame = { identity: display.identity, frame: Wallpaper.framing(value) }
    frameCommit.restart()
  }
  function commitFrame() {
    frameCommit.stop()
    if (!liveFrame || liveCommitted) return
    liveCommitted = true
    controller.frameDisplay(liveFrame.identity, liveFrame.frame)
    if (liveFrame && !liveSettled()) frameRelease.restart()
    else releaseFrame()
  }
  function liveSettled() {
    var display = { identity: liveFrame.identity }
    return JSON.stringify(Wallpaper.frameFor(scene, display)) === JSON.stringify(Wallpaper.frameFor(shownScene, display))
  }
  function releaseFrame() {
    frameRelease.stop()
    liveFrame = null
    liveCommitted = false
  }
  function selectedTile() {
    for (var i = 0; i < tiles.count; i++) {
      var tile = tiles.itemAt(i)
      if (tile && tile.modelData.name === selectedName) return tile
    }
    return tiles.count ? tiles.itemAt(0) : null
  }
  function nudgeSelected(dx, dy) {
    var tile = selectedTile()
    if (tile) tile.panBy(dx, dy)
  }
  function zoomSelected(factor) {
    var tile = selectedTile()
    if (tile) tile.zoomBy(factor, tile.modelData.width / 2, tile.modelData.height / 2)
  }
  function resetSelected() {
    var tile = selectedTile()
    if (tile) setFrame(tile.modelData, {})
    commitFrame()
  }
  function nudge(dx, dy) {
    controller.frame(Object.assign({}, scene.framing,
      { x: scene.framing.x + dx, y: scene.framing.y + dy }))
  }
  Keys.onLeftPressed: spanning ? nudge(-0.02, 0) : nudgeSelected(-0.02, 0)
  Keys.onRightPressed: spanning ? nudge(0.02, 0) : nudgeSelected(0.02, 0)
  Keys.onUpPressed: spanning ? nudge(0, -0.02) : nudgeSelected(0, -0.02)
  Keys.onDownPressed: spanning ? nudge(0, 0.02) : nudgeSelected(0, 0.02)
  Keys.onPressed: function(event) {
    if (spanning) return
    if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) zoomSelected(1.1)
    else if (event.key === Qt.Key_Minus) zoomSelected(1 / 1.1)
    else return
    event.accepted = true
  }
  Timer { id: frameCommit; interval: 150; onTriggered: root.commitFrame() }
  Timer { id: frameRelease; interval: 1000; onTriggered: root.releaseFrame() }
  Canvas {
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
      var radius = Math.max(Style.space(0.7), 0.5)
      for (var x = root.gridStep; x < width; x += root.gridStep)
        for (var y = root.gridStep; y < height; y += root.gridStep) {
          context.beginPath()
          context.arc(x, y, radius, 0, Math.PI * 2)
          context.fill()
        }
    }
  }
  Image {
    id: background
    source: root.scene.safe ? Util.fileUrl(root.scene.source)
      + (root.scene.revision ? "?station=" + encodeURIComponent(root.scene.revision) : "")
      : ""
    asynchronous: true
    width: root.readySourceSize.width * root.imageFit
    height: root.readySourceSize.height * root.imageFit
    x: (root.width - width) / 2
    y: (root.height - height) / 2
    visible: root.spanning
    fillMode: Image.PreserveAspectFit
    onStatusChanged: if (status === Image.Ready && sourceSize.width > 0 && sourceSize.height > 0)
      root.readySourceSize = sourceSize
  }
  Repeater {
    id: tiles
    model: root.layout.displays
    delegate: Item {
      id: monitor
      required property var modelData
      objectName: "wallpaperMonitor-" + modelData.name
      x: root.groupX + modelData.x * root.fit + (modelData.width * root.fit - width) / 2
      y: root.groupY + modelData.y * root.fit
      width: Math.max(1, Math.min(modelData.width * root.fit - root.monitorGap,
        (modelData.height * root.fit - root.monitorGap)
          * modelData.width / Math.max(1, modelData.height)))
      // The monitor's exact shape, so this tile shows the same crop as the desktop.
      height: Math.max(1, width * modelData.height / Math.max(1, modelData.width))
      readonly property real tileScale: width / Math.max(1, modelData.width)
      function panBy(dx, dy) {
        root.setFrame(modelData, Wallpaper.panned(modelData, tileImage.imageSize.width, tileImage.imageSize.height,
          root.frameOf(modelData), dx * modelData.width, dy * modelData.height))
      }
      function zoomBy(factor, pointX, pointY) {
        root.setFrame(modelData, Wallpaper.zoomed(modelData, tileImage.imageSize.width, tileImage.imageSize.height,
          root.frameOf(modelData), factor, pointX, pointY))
      }
      WallpaperUi.WallpaperImage {
        id: tileImage
        anchors.fill: parent
        visible: !root.spanning
        scene: root.shownScene
        layout: root.layout
        display: monitor.modelData
      }
      Ui.BorderSurface {
        anchors.fill: parent
        color: "transparent"
        borderSpec: root.spanning || root.selectedName === monitor.modelData.name
          ? Border.flat(Color.accent, Style.normalBorderWidth * 2)
          : Border.controlSpec("normal", Color.popups.text, Color.accent)
        radius: 0
      }

      MouseArea {
        id: framer
        anchors.fill: parent
        enabled: !root.spanning && !root.controller.busy
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real startX: 0
        property real startY: 0
        property var startFrame
        onPressed: function(mouse) {
          root.forceActiveFocus()
          root.selected(monitor.modelData.name)
          startX = mouse.x; startY = mouse.y; startFrame = root.frameOf(monitor.modelData)
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          root.setFrame(monitor.modelData, Wallpaper.panned(monitor.modelData,
            tileImage.imageSize.width, tileImage.imageSize.height, startFrame,
            (mouse.x - startX) / monitor.tileScale, (mouse.y - startY) / monitor.tileScale))
        }
        onReleased: root.commitFrame()
        onCanceled: root.commitFrame()
        onWheel: function(wheel) {
          root.forceActiveFocus()
          root.selected(monitor.modelData.name)
          monitor.zoomBy(Math.pow(1.1, wheel.angleDelta.y / 120),
            wheel.x / monitor.tileScale, wheel.y / monitor.tileScale)
          wheel.accepted = true
        }
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
