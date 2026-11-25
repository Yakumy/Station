import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Wallpaper.js" as Wallpaper
import "." as WallpaperUi
import "../platform" as Platform

// What the applied wallpaper draws: one surface per monitor behind the windows, and
// the theme intro's hand-off. It reads the owner's applied scene and changes nothing.
Item {
  id: root
  property var scene: ({})
  property var layout: ({ displays: [] })
  property string themePath: ""
  property string themeRevision: ""
  property string themeToken: ""
  property bool configLoaded: false

  Image {
    id: introImage
    source: root.configLoaded && root.scene.followTheme ? Util.fileUrl(root.themePath) + "?station=" + encodeURIComponent(root.themeRevision) : ""
    asynchronous: true
    visible: false
  }
  WallpaperUi.IntroPlayback {
    id: introPlayback
    enabled: root.configLoaded && root.scene.followTheme && (root.scene.mode !== "same"
      || root.layout.displays.some(function(display) { return Wallpaper.hasFrame(root.scene, display) }))
    scene: root.scene
    layout: root.layout
    themeToken: root.themeToken
    returnReady: {
      var count = 0
      for (var surface of wallpaperSurfaces.instances) {
        if (!surface.display || surface.stock) continue
        count++
        if (!surface.visible || surface.returnFrames < 2) return false
      }
      return count > 0
    }
    imageWidth: introImage.status === Image.Ready ? introImage.sourceSize.width : 0
    imageHeight: introImage.status === Image.Ready ? introImage.sourceSize.height : 0
  }
  Variants {
    id: wallpaperSurfaces
    model: Quickshell.screens
    PanelWindow {
      id: surface
      required property var modelData
      readonly property var display: root.layout.displays.find(function(d) { return d.name === modelData.name }) || null
      readonly property bool stock: root.scene.mode === "same" && root.scene.followTheme && root.scene.source === root.themePath
        && !Wallpaper.hasFrame(root.scene, display)
      property int returnFrames: 0
      onVisibleChanged: if (!visible) returnFrames = 0
      Connections {
        target: introPlayback
        function onReturningChanged() { surface.returnFrames = 0 }
      }
      FrameAnimation {
        running: introPlayback.returning && surface.visible && surface.returnFrames < 2
        onTriggered: surface.returnFrames++
      }
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "station-wallpaper"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      color: "transparent"
      visible: root.configLoaded && display !== null && !stock && wallpaper.status === Image.Ready && !remap.remapping
      Platform.ScreenMoveRemap { id: remap; window: surface }
      WallpaperUi.WallpaperImage {
        id: wallpaper
        // Keep the layer mapped: remapping invokes Hyprland's layer fade and
        // exposes the stock wallpaper beneath it during the return handoff.
        visible: !introPlayback.exposed
        anchors.fill: parent
        scene: root.scene
        layout: root.layout
        display: surface.display || ({ width: 1, height: 1, x: 0, y: 0, identity: "" })
      }
    }
  }
}
