import QtQuick
import qs.Ui as Ui
import qs.Commons
import "Model.js" as Model
import "." as Station

Column {
  id: displayTab
  required property var panelRoot
  readonly property var service: panelRoot.service
  readonly property var selectedDisplay: panelRoot.selectedDisplay
  readonly property int enabledCount: service
    ? service.displayDraft.filter(function(display) { return display.enabled }).length : 0
  // The canvas is a region and takes the shared 24px gutter. The inspector is
  // a dense column inside a ~570px popout, so it keeps the smallest step that
  // reads clearly instead of the full region padding.
  readonly property real pad: panelRoot.regionPadH
  readonly property real gutter: panelRoot.space2
  spacing: 0

  Column {
    id: mainColumn
    width: parent.width
    spacing: 0

    Row {
      id: displayColumns
      width: parent.width
      height: Math.max(leftColumn.implicitHeight, rightColumn.implicitHeight)

      Column {
        id: leftColumn
        width: parent.width * 0.65
        spacing: 0

        Item {
          id: layoutHeader
          width: parent.width
          height: panelRoot.space5
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: displayTab.pad
            anchors.verticalCenter: parent.verticalCenter
            text: "LAYOUT"
            foreground: displayTab.panelRoot.textPrimary
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: displayTab.pad
            anchors.verticalCenter: parent.verticalCenter
            text: "LOGICAL COORDINATES · DRAG TO ARRANGE"
            color: displayTab.panelRoot.textDim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Station.DisplayLayout {
          width: parent.width - displayTab.pad * 2
          height: Math.max(Style.space(228), rightColumn.implicitHeight - layoutHeader.height)
          anchors.horizontalCenter: parent.horizontalCenter
          service: displayTab.service
          panelRoot: displayTab.panelRoot
          selectedDisplayName: displayTab.panelRoot.selectedDisplayName
          onDisplaySelected: function(name) { displayTab.panelRoot.selectDisplay(name) }
        }

      }

      Rectangle {
        width: Math.max(1, Style.normalBorderWidth)
        height: displayColumns.height
        color: Color.popups.text
        opacity: 0.12
      }

      Column {
        id: rightColumn
        width: parent.width - leftColumn.width - Math.max(1, Style.normalBorderWidth)
        spacing: 0

        Item {
          width: parent.width
          height: panelRoot.space6 + panelRoot.space2
          Column {
            anchors.left: parent.left
            anchors.right: selectedEnabled.left
            anchors.leftMargin: displayTab.gutter
            anchors.rightMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs
            Text {
              width: parent.width
              text: displayTab.selectedDisplay
                ? displayTab.selectedDisplay.name + " · " + displayTab.panelRoot.roleName(displayTab.selectedDisplay) : "No display selected"
              elide: Text.ElideRight
              color: displayTab.panelRoot.textPrimary
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              width: parent.width
              text: displayTab.selectedDisplay ? displayTab.selectedDisplay.description : ""
              elide: Text.ElideRight
              color: displayTab.panelRoot.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
          Ui.Button {
            id: selectedEnabled
            anchors.right: parent.right
            anchors.rightMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            width: displayTab.panelRoot.space6
            height: displayTab.panelRoot.controlHeight
            radius: Style.cornerRadius
            text: displayTab.selectedDisplay && displayTab.selectedDisplay.enabled ? "✓" : ""
            foreground: displayTab.panelRoot.textPrimary
            onClicked: {
              if (!displayTab.service || !displayTab.selectedDisplay || displayTab.service.state !== "idle") return
              var enabled = displayTab.service.displayDraft.filter(function(display) { return display.enabled }).length
              if (displayTab.selectedDisplay.enabled && enabled <= 1) return
              displayTab.service.setDisplayValue(displayTab.selectedDisplay.name, "enabled", !displayTab.selectedDisplay.enabled)
              displayTab.service.previewLayout()
            }
          }
        }
        Ui.PanelSeparator { width: parent.width; foreground: displayTab.panelRoot.textPrimary }

        Item {
          width: parent.width
          height: panelRoot.space5
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: "BRIGHTNESS"
            foreground: displayTab.panelRoot.textPrimary
          }
          // Body-emphasis value: brighter and heavier than the eyebrow above
          // it. The monospace family keeps the digits aligned as they change.
          Text {
            anchors.right: parent.right
            anchors.rightMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.panelRoot.brightnessAvailable ? displayTab.panelRoot.brightness + "%" : "—"
            color: displayTab.panelRoot.textPrimary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.weight: Font.DemiBold
          }
        }
        Ui.PanelSlider {
          width: parent.width - displayTab.gutter * 2
          anchors.horizontalCenter: parent.horizontalCenter
          bar: displayTab.panelRoot.bar
          minimum: 1
          maximum: 100
          integer: true
          value: displayTab.panelRoot.brightness
          enabled: displayTab.panelRoot.brightnessAvailable
            && displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
          opacity: enabled ? 1 : displayTab.panelRoot.disabledOpacity
          onMoved: function(value) { displayTab.panelRoot.brightness = Math.round(value) }
          onReleased: function(value) { displayTab.panelRoot.queueBrightness(value) }
        }
        Text {
          visible: !displayTab.panelRoot.brightnessAvailable
          width: parent.width - displayTab.gutter * 2
          x: displayTab.gutter
          text: "Not available for this display"
          color: displayTab.panelRoot.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Item { width: 1; height: displayTab.gutter }
        Ui.PanelSeparator { width: parent.width; foreground: displayTab.panelRoot.textPrimary }

        Item {
          width: parent.width
          height: panelRoot.space5
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: "SCALE"
            foreground: displayTab.panelRoot.textPrimary
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.selectedDisplay ? displayTab.selectedDisplay.name : ""
            color: displayTab.panelRoot.textDim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Ui.ButtonGroup {
          id: scaleGroup
          width: parent.width - displayTab.gutter * 2
          anchors.horizontalCenter: parent.horizontalCenter
          foreground: displayTab.panelRoot.textPrimary
          background: Color.popups.background
          accent: Color.accent
          options: [1, 1.25, 1.6, 2, 3, 4].map(function(scale) {
            return { value: String(scale), label: scale + "x" }
          })
          value: displayTab.selectedDisplay
            ? String(Number(displayTab.selectedDisplay.scale)) : ""
          onChanged: function(value) {
            if (!displayTab.service || !displayTab.selectedDisplay || displayTab.service.state !== "idle") return
            displayTab.service.setDisplayValue(displayTab.selectedDisplay.name, "scale", Number(value))
            displayTab.service.previewLayout()
          }
        }
        Item { width: 1; height: displayTab.gutter }
        Ui.PanelSeparator { width: parent.width; foreground: displayTab.panelRoot.textPrimary }

        Item {
          width: parent.width
          height: panelRoot.space5
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: "RESOLUTION · REFRESH"
            foreground: displayTab.panelRoot.textPrimary
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.selectedDisplay ? displayTab.selectedDisplay.name : ""
            color: displayTab.panelRoot.textDim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Row {
          width: parent.width - displayTab.gutter * 2
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: displayTab.gutter
          Ui.Dropdown {
            width: (parent.width - parent.spacing) / 2
            showLabel: false
            value: displayTab.selectedDisplay && Model.parseMode(displayTab.selectedDisplay.mode)
              ? Model.parseMode(displayTab.selectedDisplay.mode).width + "x"
                + Model.parseMode(displayTab.selectedDisplay.mode).height : ""
            options: displayTab.selectedDisplay
              ? Model.resolutionChoices(displayTab.selectedDisplay.availableModes) : []
            foreground: displayTab.panelRoot.textPrimary
            onChanged: function(value) {
              if (!displayTab.service || !displayTab.selectedDisplay || displayTab.service.state !== "idle") return
              var exact = Model.modeForResolution(displayTab.selectedDisplay.availableModes,
                value, displayTab.selectedDisplay.mode)
              displayTab.service.setDisplayValue(displayTab.selectedDisplay.name, "mode", exact)
              displayTab.service.previewLayout()
            }
          }
          Ui.Dropdown {
            width: (parent.width - parent.spacing) / 2
            showLabel: false
            value: displayTab.selectedDisplay ? displayTab.selectedDisplay.mode : ""
            options: displayTab.selectedDisplay && Model.parseMode(displayTab.selectedDisplay.mode)
              ? Model.refreshChoices(displayTab.selectedDisplay.availableModes,
                Model.parseMode(displayTab.selectedDisplay.mode).width + "x"
                  + Model.parseMode(displayTab.selectedDisplay.mode).height) : []
            foreground: displayTab.panelRoot.textPrimary
            onChanged: function(value) {
              if (!displayTab.service || !displayTab.selectedDisplay || displayTab.service.state !== "idle") return
              displayTab.service.setDisplayValue(displayTab.selectedDisplay.name, "mode", value)
              displayTab.service.previewLayout()
            }
          }
        }
        Item { width: 1; height: displayTab.gutter }
        Ui.PanelSeparator { width: parent.width; foreground: displayTab.panelRoot.textPrimary }

        Item {
          width: parent.width
          height: panelRoot.space5
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: "ROLE"
            foreground: displayTab.panelRoot.textPrimary
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: displayTab.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.selectedDisplay ? displayTab.selectedDisplay.name : ""
            color: displayTab.panelRoot.textDim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Ui.ButtonGroup {
          id: roleGroup
          width: parent.width - displayTab.gutter * 2
          anchors.horizontalCenter: parent.horizontalCenter
          foreground: displayTab.panelRoot.textPrimary
          background: Color.popups.background
          accent: Color.accent
          options: ["Primary", "Secondary", "Third"].slice(0, displayTab.enabledCount)
            .map(function(label, index) { return { value: String(index), label: label } })
          value: displayTab.service && displayTab.selectedDisplay
            ? String(displayTab.service.roleOf(displayTab.selectedDisplay.name)) : ""
          onChanged: function(value) {
            if (!displayTab.service || !displayTab.selectedDisplay || displayTab.service.state !== "idle") return
            displayTab.service.swapRole(displayTab.selectedDisplay.name, Number(value))
          }
        }
        Text {
          width: parent.width - displayTab.gutter * 2
          x: displayTab.gutter
          topPadding: displayTab.gutter
          text: displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
            ? "Lane " + displayTab.selectedDisplay.lane : "Enable this display to assign a role"
          color: displayTab.panelRoot.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Item { width: 1; height: displayTab.gutter }
      }
    }

    Item {
      visible: displayTab.service && displayTab.service.layoutError !== ""
        && displayTab.service.state !== "previewing"
      width: parent.width
      height: visible ? errorText.implicitHeight + displayTab.gutter * 2 : 0
      Ui.PanelSeparator { width: parent.width; foreground: Color.urgent }
      Text {
        id: errorText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: displayTab.gutter
        anchors.rightMargin: displayTab.gutter
        anchors.verticalCenter: parent.verticalCenter
        text: displayTab.service ? displayTab.service.layoutError : ""
        wrapMode: Text.WordWrap
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      width: parent.width
      // Reserve the preview footer from the start so Keep/Revert never
      // changes the panel height or shifts the canvas.
      height: Style.space(46)
      readonly property bool previewing: displayTab.service && displayTab.service.state === "previewing"
      Ui.PanelSeparator {
        visible: parent.previewing
        width: parent.width
        foreground: displayTab.panelRoot.textPrimary
      }
      Text {
        visible: parent.previewing
        anchors.left: parent.left
        anchors.leftMargin: displayTab.gutter
        anchors.right: revertButton.left
        anchors.rightMargin: displayTab.gutter
        anchors.verticalCenter: parent.verticalCenter
        text: "Keep these settings? Reverting in "
          + (displayTab.service ? displayTab.service.previewSeconds : 0) + " s"
        color: displayTab.panelRoot.textPrimary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Ui.Button {
        id: keepButton
        visible: parent.previewing
        anchors.right: parent.right
        anchors.rightMargin: displayTab.gutter
        anchors.verticalCenter: parent.verticalCenter
        height: displayTab.panelRoot.controlHeight
        radius: Style.cornerRadius
        text: "Keep"
        // Keep is the primary action, so it carries the accent fill.
        accent: Color.accent
        background: Color.accent
        foreground: Color.popups.background
        onClicked: displayTab.service.keepPreview()
      }
      Ui.Button {
        id: revertButton
        visible: parent.previewing
        anchors.right: keepButton.left
        anchors.rightMargin: displayTab.gutter
        anchors.verticalCenter: parent.verticalCenter
        height: displayTab.panelRoot.controlHeight
        radius: Style.cornerRadius
        text: "Revert"
        bordered: true
        foreground: Color.popups.text
        onClicked: displayTab.service.revertPreview("")
      }
    }
  }
}
