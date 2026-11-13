import QtQuick
import "../panel" as PanelUi
import qs.Ui as Ui
import qs.Commons
import "Wallpaper.js" as Wallpaper
import "." as WallpaperUi

Column {
  id: root
  required property var tokens
  required property var dismiss
  required property var controller
  property bool narrow: false
  readonly property var scene: controller ? controller.draft : Wallpaper.resolve({}, "", "")
  property string selectedName: ""
  readonly property var selectedDisplay: controller ? (controller.layout.displays.find(function(d) {
    return d.name === root.selectedName
  }) || controller.layout.displays[0] || null) : null
  readonly property real pad: tokens.regionPadH
  spacing: 0
  component Caption: Text {
    textFormat: Text.PlainText
    color: root.tokens.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
  function fileName(path) { return String(path || "").split("/").pop() }
  readonly property string imagePath: scene.mode === "individual" && selectedDisplay
    ? (scene.perDisplay[selectedDisplay.identity] || scene.source) : scene.source
  component RowTitle: PanelUi.ControlLabel {}
  component RowHint: Caption {
    anchors.left: parent.left; anchors.leftMargin: root.tokens.space2
    anchors.right: parent.right; anchors.rightMargin: root.tokens.space2
    anchors.bottom: parent.bottom; anchors.bottomMargin: root.tokens.space1
    wrapMode: Text.NoWrap
    elide: Text.ElideRight
  }
  component RowDropdown: PanelUi.ControlDropdown {
    showLabel: false
    foreground: root.tokens.textPrimary
  }
  component RowButton: PanelUi.ControlButton {}

  PanelUi.FeatureGeometry { id: geometry }

  Item {
    id: wallpaperColumns
    width: parent.width
    height: root.narrow ? geometry.stackedHeight : Style.space(428)
    Column {
      id: left
      width: root.narrow ? wallpaperColumns.width : wallpaperColumns.width * 0.576
      Item {
        width: parent.width; height: geometry.headingHeight
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "LAYOUT"; foreground: Color.popups.text
        }
        Caption {
          anchors.right: parent.right; anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: root.scene.mode === "span" ? "DRAG TO ARRANGE" : "DRAG TO FRAME · SCROLL TO ZOOM"
        }
      }
      Loader {
        objectName: "featureLayoutFrame"
        id: canvasLoader
        x: root.pad; width: parent.width - root.pad * 2
        height: geometry.frameHeight
        active: root.controller !== null
        sourceComponent: WallpaperUi.WallpaperLayout {
          controller: root.controller
          selectedName: root.selectedDisplay ? root.selectedDisplay.name : ""
          onSelected: function(name) { root.selectedName = name }
        }
      }
      Caption {
        id: layoutHint
        parent: canvasLoader
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.tokens.space2
        wrapMode: Text.WordWrap
        x: root.pad; width: parent.width - root.pad * 2
        topPadding: root.tokens.space2
        text: {
          if (!root.controller) return ""
          if (root.scene.mode !== "span") return "Monitor positions follow Displays. Only active displays are shown."
          var size = Wallpaper.recommendation(root.controller.layout, root.scene.framing)
          return "Recommended minimum: " + size.width + " × " + size.height + " px. Smaller images work, but may look soft."
        }
      }
    }
    Item {
      x: root.narrow ? 0 : left.width
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight : 0
      width: root.narrow ? wallpaperColumns.width : Math.max(1, Style.normalBorderWidth)
      height: root.narrow ? geometry.separatorSlot : Style.space(428)
      Rectangle {
        objectName: "featureDivider"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.narrow ? geometry.halfGap - height / 2 : 0
        width: root.narrow ? parent.width : Math.max(1, Style.normalBorderWidth)
        height: root.narrow ? Math.max(1, Style.normalBorderWidth) : parent.height
        color: Color.popups.text; opacity: 0.12
      }
    }
    Column {
      x: root.narrow ? 0 : left.width + Math.max(1, Style.normalBorderWidth)
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight + geometry.separatorSlot : 0
      id: rightColumn
      width: root.narrow ? wallpaperColumns.width
        : wallpaperColumns.width - left.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      enabled: root.controller && !root.controller.busy && !root.controller.importBusy
      Item {
        width: parent.width; height: geometry.headingHeight
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: geometry.headingHeight
          anchors.verticalCenter: parent.verticalCenter
          objectName: "wallpaperSelectedMonitor"
          text: root.scene.mode === "individual" && root.selectedDisplay
            ? "Selected: " + root.selectedDisplay.name : ""
          foreground: Color.popups.text
        }
      }
      PanelUi.ControlFrame {
        objectName: "featureControlFrame"
        narrow: root.narrow
        id: controlFrame
        height: geometry.frameHeight
        Column {
          anchors.fill: parent
          spacing: 0
          Item {
            id: modeRow
            width: parent.width; height: controlFrame.height / 5
            RowTitle { text: "Mode" }
            RowDropdown {
              id: modeDropdown
              objectName: "wallpaperModeDropdown"
              options: [{ value: "span", label: "Span" }, { value: "individual", label: "Per monitor" }, { value: "same", label: "Same on all" }]
              onChanged: function(value) { root.controller.change("mode", value) }
            }
            Binding { target: modeDropdown; property: "value"; value: root.scene.mode }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Color.popups.text }
          }
          Item {
            id: followRow
            width: parent.width; height: controlFrame.height / 5
            RowTitle { text: "Follow Omarchy theme" }
            RowDropdown {
              id: followDropdown
              objectName: "wallpaperFollowDropdown"
              options: [{ value: "yes", label: "Yes" }, { value: "no", label: "No" }]
              onChanged: function(value) { root.controller.change("followTheme", value === "yes") }
            }
            Binding { target: followDropdown; property: "value"; value: root.scene.followTheme ? "yes" : "no" }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Color.popups.text }
          }
          Item {
            id: imageRow
            width: parent.width; height: controlFrame.height / 5
            RowTitle { text: "Image" }
            RowButton {
              objectName: "wallpaperChooseImage"
              text: "Choose image…"
              enabled: root.selectedDisplay !== null && root.controller && !root.controller.pickerBusy
              onClicked: {
                var target = root.scene.mode === "individual" ? root.selectedDisplay.identity : ""
                var owner = root.controller
                if (owner.choose(target)) root.dismiss()
              }
            }
            RowHint { objectName: "wallpaperImageHint"; text: root.fileName(root.imagePath) }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 5
            RowTitle { text: "Theme background" }
            RowButton {
              objectName: "wallpaperThemeBackground"
              text: "Choose theme background…"
              onClicked: root.controller.openMenu("background")
            }
            RowHint { text: root.controller ? root.fileName(root.controller.themePath) : "" }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 5
            RowTitle { text: "Theme" }
            RowButton {
              objectName: "wallpaperThemePicker"
              text: "Choose theme…"
              onClicked: root.controller.openMenu("theme")
            }
            RowHint { text: root.controller ? root.controller.themeName : "" }
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }
  Item {
    width: parent.width
    height: root.narrow && !(root.controller && root.controller.dirty) ? 0 : (root.narrow ? geometry.actionHeight : Style.space(64))
    clip: true
    Caption {
      id: drawerNotice
      visible: text.length > 0
      x: root.pad; anchors.verticalCenter: root.narrow ? undefined : parent.verticalCenter
      anchors.top: root.narrow ? parent.top : undefined
      anchors.topMargin: root.tokens.space2
      width: root.narrow ? parent.width - root.pad * 2 : parent.width - actions.width - root.pad * 3
      anchors.bottom: root.narrow ? actions.top : undefined
      anchors.bottomMargin: root.tokens.space1
      elide: Text.ElideRight
      wrapMode: Text.WordWrap
      text: root.controller ? root.controller.notice : ""
      color: root.controller && root.controller.noticeError ? Color.urgent : root.tokens.textDim
    }
    Row {
      id: actions
      anchors.right: parent.right; anchors.rightMargin: root.pad
      anchors.verticalCenter: root.narrow && drawerNotice.text.length > 0 ? undefined : parent.verticalCenter
      anchors.bottom: root.narrow && drawerNotice.text.length > 0 ? parent.bottom : undefined
      anchors.bottomMargin: root.tokens.space2
      spacing: root.tokens.space2
      PanelUi.ActionButton {
        widthFactor: 0.6
        text: "Cancel"; bordered: true
        enabled: root.controller && root.controller.dirty && !root.controller.busy && !root.controller.importBusy
        onClicked: root.controller.reset()
      }
      PanelUi.ActionButton {
        widthFactor: 0.6
        text: root.controller && root.controller.importBusy ? "Preparing…"
          : root.controller && root.controller.busy ? "Applying…" : "Apply"
        accent: Color.accent
        background: Color.accent
        foreground: Color.popups.background
        enabled: root.controller && root.controller.dirty && !root.controller.busy
          && !root.controller.importBusy && root.controller.layout.displays.length > 0
        onClicked: root.controller.apply()
      }
    }
  }
}
