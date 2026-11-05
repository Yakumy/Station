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
  readonly property size imageSize: picture.sourceSize
  function imageUrl(path) {
    if (!scene.safe) return ""
    var url = Util.fileUrl(path)
    return path === scene.source && scene.revision ? url + "?station=" + encodeURIComponent(scene.revision) : url
  }
  clip: true

  Image {
    id: picture
    readonly property var crop: Wallpaper.crop(root.scene, root.layout, root.display, sourceSize.width, sourceSize.height)
    // The larger scale, so a surface a pixel off the logical size still leaves no edge.
    readonly property real unit: Math.max(root.width / Math.max(1, crop.width),
      root.height / Math.max(1, crop.height))
    source: root.imageUrl(Wallpaper.sourceFor(root.scene, root.display))
    asynchronous: true
    cache: true
    x: -crop.x * unit
    y: -crop.y * unit
    width: sourceSize.width * unit
    height: sourceSize.height * unit
  }
}
