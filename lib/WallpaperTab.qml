import QtQuick
import qs.Ui as Ui
import qs.Commons
import "Wallpaper.js" as Wallpaper
import "." as Station

Column {
  id: root
  required property var panelRoot
  readonly property var controller: panelRoot.service ? panelRoot.service.wallpaper : null
  readonly property var scene: controller ? controller.draft : Wallpaper.resolve({}, "", "")
  property string selectedName: ""
  readonly property var selectedDisplay: controller ? (controller.layout.displays.find(function(d) {
    return d.name === root.selectedName
  }) || controller.layout.displays[0] || null) : null
  readonly property real pad: panelRoot.regionPadH
  spacing: 0
  component Caption: Text {
    color: root.panelRoot.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
  Row {
    width: parent.width
    height: Style.space(428)
    Column {
      id: left
      width: parent.width * 0.576
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "LAYOUT"; foreground: Color.popups.text
        }
        Caption {
          anchors.right: parent.right; anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: root.scene.mode === "span" ? "DRAG GROUP · SCROLL TO ZOOM" : "SELECT A MONITOR"
        }
      }
      Loader {
        id: canvasLoader
        x: root.pad; width: parent.width - root.pad * 2; height: Style.space(340)
        active: root.controller !== null
        sourceComponent: Station.WallpaperLayout {
          controller: root.controller
          selectedName: root.selectedDisplay ? root.selectedDisplay.name : ""
          onSelected: function(name) { root.selectedName = name }
        }
      }
      Caption {
        x: root.pad; width: parent.width - root.pad * 2
        topPadding: root.panelRoot.space2
        text: {
          if (!root.controller) return ""
          if (root.scene.mode !== "span") return "Monitor positions follow Displays. Only active displays are shown."
          var size = Wallpaper.recommendation(root.controller.layout, root.scene.framing)
          return "Recommended minimum: " + size.width + " × " + size.height + " px. Smaller images work, but may look soft."
        }
      }
    }
    Rectangle {
      width: Math.max(1, Style.normalBorderWidth); height: parent.height
      color: Color.popups.text; opacity: 0.12
    }
    Column {
      id: controls
      width: parent.width - left.width - Math.max(1, Style.normalBorderWidth)
      spacing: root.panelRoot.space3
      enabled: root.controller && !root.controller.busy
      Item { width: 1; height: root.panelRoot.space2 }
      Ui.PanelSectionHeader {
        x: root.pad; width: parent.width - root.pad * 2
        text: "WALLPAPER"; foreground: Color.popups.text
      }
      Station.InlineDropdown {
        x: root.pad
        prefix: "Mode: "
        value: root.scene.mode
        options: [{ value: "same", label: "Same on all" }, { value: "individual", label: "Per monitor" }, { value: "span", label: "Span" }]
        onChanged: function(value) { root.controller.change("mode", value) }
      }
      Station.InlineDropdown {
        x: root.pad
        visible: root.scene.mode === "individual"
        prefix: "Monitor: "
        value: root.selectedDisplay ? root.selectedDisplay.name : ""
        options: root.controller ? root.controller.layout.displays.map(function(d) { return { value: d.name, label: d.name } }) : []
        onChanged: function(value) { root.selectedName = value }
      }
      Ui.Button {
        x: root.pad; text: "Choose image…"; bordered: true
        enabled: root.selectedDisplay !== null && root.controller && !root.controller.pickerBusy
        onClicked: {
          var target = root.scene.mode === "individual" ? root.selectedDisplay.identity : ""
          var owner = root.controller
          root.panelRoot.close()
          owner.choose(target)
        }
      }
      Ui.Button {
        x: root.pad; text: "Use Omarchy wallpaper"; bordered: true
        enabled: root.controller && root.controller.themePath !== ""
        onClicked: root.controller.useTheme()
      }
      Caption {
        x: root.pad; width: parent.width - root.pad * 2
        text: root.scene.mode === "span" ? "Move the monitors together over the fixed image. Zoom in for a tighter crop."
          : root.scene.mode === "individual" ? "Select a monitor, then choose its image." : "One image, fitted separately on every monitor."
      }
      Row {
        x: root.pad; spacing: root.panelRoot.space2
        visible: root.scene.mode === "span"
        Ui.Button { text: "−"; bordered: true; onClicked: canvasLoader.item.zoom(1 / 1.2) }
        Ui.Button { text: "+"; bordered: true; onClicked: canvasLoader.item.zoom(1.2) }
        Ui.Button { text: "Fit"; bordered: true; onClicked: root.controller.frame({}) }
      }
      Ui.PanelSeparator { x: root.pad; width: parent.width - root.pad * 2; foreground: Color.popups.text }
      Item {
        x: root.pad; width: parent.width - root.pad * 2; height: Style.space(30)
        Caption { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Follow Omarchy wallpaper" }
        Ui.ToggleSwitch {
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          checked: root.scene.followTheme
          trackHeight: Style.spacing.controlHeight
          foreground: Color.popups.text
          onToggled: root.controller.change("followTheme", !checked)
        }
      }
      Caption {
        x: root.pad; width: parent.width - root.pad * 2
        text: root.scene.followTheme ? "Follows theme and background changes; remembers your choices when you return."
          : "Keeps these images when the theme or background changes."
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }
  Item {
    width: parent.width; height: Style.space(64)
    Caption {
      x: root.pad; anchors.verticalCenter: parent.verticalCenter
      width: parent.width - actions.width - root.pad * 3
      text: root.controller ? root.controller.notice : ""
    }
    Row {
      id: actions
      anchors.right: parent.right; anchors.rightMargin: root.pad
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.panelRoot.space2
      Ui.Button {
        text: "Cancel"; bordered: true
        enabled: root.controller && root.controller.dirty && !root.controller.busy
        onClicked: root.controller.reset()
      }
      Ui.Button {
        text: root.controller && root.controller.busy ? "Applying…" : "Apply"
        accent: Color.accent
        background: Color.accent
        foreground: Color.popups.background
        enabled: root.controller && root.controller.dirty && !root.controller.busy && root.controller.layout.displays.length > 0
        onClicked: root.controller.apply()
      }
    }
  }
}
