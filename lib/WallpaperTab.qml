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
  component ModeSelector: Ui.BorderSurface {
    id: selector
    property string value: ""
    property var options: []
    signal changed(string value)
    color: Color.popups.background
    borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
    radius: Style.cornerRadius
    clip: true

    Row {
      anchors.fill: parent
      anchors.margins: Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Repeater {
        model: selector.options
        delegate: Item {
          required property var modelData
          required property int index
          width: (selector.width - Math.max(1, Style.normalBorderWidth) * 2) / selector.options.length
          height: parent.height
          Ui.Button {
            anchors.fill: parent
            text: modelData.label
            selected: selector.value === modelData.value
            focusable: true
            foreground: Color.popups.text
            background: Color.popups.background
            accent: Color.accent
            onClicked: selector.changed(modelData.value)
          }
          Rectangle {
            visible: index > 0
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Style.normalBorderWidth)
            color: Border.color(Border.controlSpec("normal", Color.popups.text, Color.accent))
          }
        }
      }
    }
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
          text: "DRAG TO ARRANGE"
        }
      }
      Loader {
        id: canvasLoader
        x: root.pad; width: parent.width - root.pad * 2; height: Style.space(370)
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
      id: rightColumn
      width: parent.width - left.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      enabled: root.controller && !root.controller.busy
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          text: "WALLPAPER"; foreground: Color.popups.text
        }
      }
      Ui.BorderSurface {
        id: controlFrame
        width: parent.width - Style.space(28) * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Color.popups.background
        borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)
        radius: Style.cornerRadius
        Column {
          anchors.fill: parent
          spacing: 0
          Item {
            width: parent.width; height: controlFrame.height / 3
            Caption {
              anchors.left: parent.left; anchors.leftMargin: root.panelRoot.space3
              anchors.top: parent.top; anchors.topMargin: root.panelRoot.space3
              text: "MODE"
            }
            Station.InlineDropdown {
              anchors.right: parent.right; anchors.rightMargin: root.panelRoot.space3
              anchors.top: parent.top; anchors.topMargin: root.panelRoot.space2
              visible: root.scene.mode === "individual"
              prefix: "Monitor: "
              value: root.selectedDisplay ? root.selectedDisplay.name : ""
              options: root.controller ? root.controller.layout.displays.map(function(d) { return { value: d.name, label: d.name } }) : []
              onChanged: function(value) { root.selectedName = value }
            }
            ModeSelector {
              anchors.left: parent.left; anchors.leftMargin: root.panelRoot.space3
              anchors.right: parent.right; anchors.rightMargin: root.panelRoot.space3
              anchors.bottom: parent.bottom; anchors.bottomMargin: root.panelRoot.space3
              height: Style.space(58)
              value: root.scene.mode
              options: [{ value: "span", label: "Span" }, { value: "individual", label: "Per monitor" }, { value: "same", label: "Same on all" }]
              onChanged: function(value) { root.controller.change("mode", value) }
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 3
            Row {
              anchors.left: parent.left; anchors.leftMargin: root.panelRoot.space3
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.panelRoot.space2
              Ui.Button {
                text: "Choose image…"; bordered: true
                enabled: root.selectedDisplay !== null && root.controller && !root.controller.pickerBusy
                onClicked: {
                  var target = root.scene.mode === "individual" ? root.selectedDisplay.identity : ""
                  var owner = root.controller
                  root.panelRoot.close()
                  owner.choose(target)
                }
              }
              Ui.Button {
                text: "Use Omarchy wallpaper"; bordered: true
                enabled: root.controller && root.controller.themePath !== ""
                onClicked: root.controller.useTheme()
              }
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 3
            Caption {
              anchors.left: parent.left; anchors.leftMargin: root.panelRoot.space3
              anchors.verticalCenter: parent.verticalCenter
              text: "Follow Omarchy wallpaper"
            }
            Ui.ToggleSwitch {
              anchors.right: parent.right; anchors.rightMargin: root.panelRoot.space3
              anchors.verticalCenter: parent.verticalCenter
              checked: root.scene.followTheme
              trackHeight: Style.spacing.controlHeight
              foreground: Color.popups.text
              onToggled: root.controller.change("followTheme", !checked)
            }
          }
        }
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
