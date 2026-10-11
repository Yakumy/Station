import QtQuick
import qs.Commons
import "Wallpaper.js" as Wallpaper

// Render the same source-space rectangle in a thumbnail or a desktop surface.
Item {
  id: root
  required property var scene
  required property var layout
  required property var display
  readonly property alias status: picture.status
  function imageUrl(path) {
    var url = Util.fileUrl(path)
    return path === scene.source && scene.revision ? url + "?station=" + encodeURIComponent(scene.revision) : url
  }
  clip: true

  Image {
    id: picture
    readonly property bool spanning: root.scene.mode === "span"
    readonly property var crop: Wallpaper.composition(root.layout, sourceSize.width, sourceSize.height, root.scene.framing)
    readonly property real unit: root.width / Math.max(1, root.display.width * crop.unit)
    source: root.imageUrl(Wallpaper.sourceFor(root.scene, root.display))
    asynchronous: true
    cache: true
    x: spanning ? -(crop.x + root.display.x * crop.unit) * unit : 0
    y: spanning ? -(crop.y + root.display.y * crop.unit) * unit : 0
    width: spanning ? sourceSize.width * unit : root.width
    height: spanning ? sourceSize.height * unit : root.height
    fillMode: spanning ? Image.Stretch : Image.PreserveAspectCrop
  }
}
