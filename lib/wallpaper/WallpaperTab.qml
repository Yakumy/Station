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
  // "theme" or "background" while a chooser covers the layout canvas.
  property string picker: ""
  readonly property bool individual: scene.mode === "individual" && selectedDisplay !== null
  readonly property string themeShown: controller ? (controller.pendingTheme || controller.themeName) : ""
  readonly property var themeEntry: controller ? Wallpaper.themeEntry(controller.themes, themeShown) : null
  readonly property var pickerItems: {
    if (!controller) return []
    if (picker === "theme") return controller.themes.map(function(theme) {
      return { key: theme.name, image: theme.preview,
        label: theme.label + (theme.name === root.controller.themeName ? " · current" : "") }
    })
    if (picker === "background" && themeEntry) return themeEntry.backgrounds.map(function(background) {
      return { key: background.path, image: background.path, label: background.file }
    })
    return []
  }
  readonly property string pickerCurrent: {
    if (!controller) return ""
    if (picker === "theme") return themeShown
    if (!themeEntry) return ""
    if (controller.pendingBackground) return controller.pendingBackground
    var live = themeEntry.backgrounds.find(function(background) { return background.omarchy === root.controller.themePath })
    return live ? live.path : themeEntry["default"]
  }
  function openPicker(kind) {
    if (!controller || controller.busy || controller.importBusy) return
    controller.loadThemes()
    picker = kind
  }
  function closePicker() {
    picker = ""
    if (canvasLoader.item) canvasLoader.item.forceActiveFocus()
  }
  function pick(key) {
    var owner = root.controller
    if (picker === "theme") owner.previewTheme(key)
    else owner.previewBackground(key, root.individual ? root.selectedDisplay.identity : "")
    closePicker()
  }
  onVisibleChanged: if (!visible) picker = ""
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
          objectName: "wallpaperCanvasHeading"
          text: root.picker === "theme" ? "THEME"
            : root.picker === "background" ? (root.individual ? "BACKGROUND · " + root.selectedDisplay.name : "BACKGROUND")
            : "LAYOUT"
          foreground: Color.popups.text
        }
        Caption {
          anchors.right: parent.right; anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: root.picker ? "← → TO BROWSE"
            : root.scene.mode === "span" ? "DRAG TO ARRANGE" : "DRAG TO FRAME · SCROLL TO ZOOM"
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
          contentVisible: root.picker === ""
          onSelected: function(name) { root.selectedName = name }
        }
      }
      Loader {
        id: pickerLoader
        parent: canvasLoader
        anchors.fill: parent
        z: 2
        active: root.picker !== "" && root.controller !== null
        onLoaded: item.forceActiveFocus()
        sourceComponent: WallpaperUi.ThemeCarousel {
          objectName: "wallpaperThemeCarousel"
          tokens: root.tokens
          items: root.pickerItems
          current: root.pickerCurrent
          emptyText: root.controller && root.controller.themesLoading ? "Loading themes…"
            : root.picker === "theme" ? "No Omarchy themes found" : "This theme has no still backgrounds"
          onPicked: function(key) { root.pick(key) }
          onClosed: root.closePicker()
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
        visible: root.picker === ""
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
              onClicked: root.openPicker("background")
            }
            RowHint {
              objectName: "wallpaperThemeBackgroundHint"
              text: !root.controller ? ""
                : root.controller.pendingBackground ? root.fileName(root.controller.pendingBackground) + " · on Apply"
                : root.fileName(root.controller.themePath)
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 5
            RowTitle { text: "Theme" }
            RowButton {
              objectName: "wallpaperThemePicker"
              text: "Choose theme…"
              onClicked: root.openPicker("theme")
            }
            RowHint {
              objectName: "wallpaperThemeHint"
              text: !root.controller ? ""
                : root.controller.pendingTheme ? (root.themeEntry ? root.themeEntry.label : root.controller.pendingTheme) + " · on Apply"
                : root.controller.themeName
            }
          }
        }
      }
    }
  }
  PanelUi.ActionDrawer {
    id: actionDrawer
    width: parent.width
    tokens: root.tokens
    narrow: root.narrow
    open: !!(root.controller && root.controller.dirty) || root.picker !== ""
    // While a chooser is open its keys take the message line, like other tabs' hints.
    message: root.picker ? "Press Enter to select · Esc to go back"
      : root.controller ? root.controller.notice : ""
    messageColor: !root.picker && root.controller && root.controller.noticeError ? Color.urgent : root.tokens.textDim
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
