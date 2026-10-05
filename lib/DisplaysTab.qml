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
          width: parent.width
          height: Style.space(30)
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "LAYOUT"
            foreground: Color.popups.text
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "LOGICAL COORDINATES · DRAG TO ARRANGE"
            color: Qt.darker(Color.popups.text, 1.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Station.DisplayLayout {
          width: parent.width - Style.spacing.md * 2
          height: Style.space(228)
          anchors.horizontalCenter: parent.horizontalCenter
          service: displayTab.service
          selectedDisplayName: displayTab.panelRoot.selectedDisplayName
          onDisplaySelected: function(name) { displayTab.panelRoot.selectDisplay(name) }
        }

        Item { width: 1; height: Style.spacing.sm }
        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

        Item {
          width: parent.width
          height: Style.space(28)
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "DISPLAYS"
            foreground: Color.popups.text
          }
        }

        Repeater {
          model: displayTab.service ? displayTab.service.displayDraft : []
          delegate: Ui.BorderSurface {
            id: displayRow
            required property var modelData
            width: leftColumn.width
            height: Style.space(34)
            color: displayTab.panelRoot.selectedDisplayName === modelData.name
              ? Color.menu.selectedBackground : "transparent"
            borderSpec: Border.none()
            radius: Style.cornerRadius
            opacity: modelData.enabled ? 1 : 0.55

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: displayTab.panelRoot.selectDisplay(displayRow.modelData.name)
            }
            Row {
              anchors.left: parent.left
              anchors.right: enabledButton.left
              anchors.leftMargin: Style.spacing.md
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm
              Text {
                text: displayRow.modelData.name + " · " + displayTab.panelRoot.roleName(displayRow.modelData)
                color: displayTab.panelRoot.selectedDisplayName === displayRow.modelData.name
                  ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                width: Math.max(0, parent.width - x)
                text: displayRow.modelData.description
                elide: Text.ElideRight
                color: Qt.darker(displayTab.panelRoot.selectedDisplayName === displayRow.modelData.name
                  ? Color.menu.selectedText : Color.menu.text, 1.35)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
            Ui.Button {
              id: enabledButton
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              text: displayRow.modelData.enabled ? "✓" : ""
              foreground: Color.menu.text
              onClicked: {
                if (!displayTab.service || displayTab.service.state !== "idle") return
                var count = displayTab.service.displayDraft.filter(function(display) { return display.enabled }).length
                if (displayRow.modelData.enabled && count <= 1) return
                displayTab.service.setDisplayValue(displayRow.modelData.name, "enabled", !displayRow.modelData.enabled)
                displayTab.service.previewLayout()
              }
            }
          }
        }

        Text {
          visible: displayTab.service && displayTab.service.unmanaged.length > 0
          width: parent.width - Style.spacing.md * 2
          x: Style.spacing.md
          wrapMode: Text.WordWrap
          text: "Station manages three displays. Mirror or disable: "
            + (displayTab.service ? displayTab.service.unmanaged.join(", ") : "")
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        width: Math.max(1, Style.normalBorderWidth)
        height: displayColumns.height
        color: Color.popups.border
      }

      Column {
        id: rightColumn
        width: parent.width - leftColumn.width - Math.max(1, Style.normalBorderWidth)
        spacing: 0

        Item {
          width: parent.width
          height: Style.space(30)
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "BRIGHTNESS"
            foreground: Color.popups.text
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.panelRoot.brightnessAvailable ? displayTab.panelRoot.brightness + "%" : "—"
            color: Qt.darker(Color.popups.text, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Ui.PanelSlider {
          width: parent.width - Style.spacing.md * 2
          anchors.horizontalCenter: parent.horizontalCenter
          bar: displayTab.panelRoot.bar
          minimum: 1
          maximum: 100
          integer: true
          value: displayTab.panelRoot.brightness
          enabled: displayTab.panelRoot.brightnessAvailable
            && displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
          opacity: enabled ? 1 : 0.35
          onMoved: function(value) { displayTab.panelRoot.brightness = Math.round(value) }
          onReleased: function(value) { displayTab.panelRoot.queueBrightness(value) }
        }
        Text {
          visible: !displayTab.panelRoot.brightnessAvailable
          width: parent.width - Style.spacing.md * 2
          x: Style.spacing.md
          text: "Not available for this display"
          color: Qt.darker(Color.popups.text, 1.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Item { width: 1; height: Style.spacing.sm }
        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

        Item {
          width: parent.width
          height: Style.space(30)
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "SCALE"
            foreground: Color.popups.text
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.selectedDisplay ? displayTab.selectedDisplay.name : ""
            color: Qt.darker(Color.popups.text, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Grid {
          id: scaleGrid
          width: parent.width - Style.spacing.md * 2
          anchors.horizontalCenter: parent.horizontalCenter
          columns: 6
          spacing: Style.spacing.xs
          Repeater {
            model: [1, 1.25, 1.6, 2, 3, 4]
            delegate: Ui.Button {
              required property real modelData
              width: (scaleGrid.width - scaleGrid.spacing * 5) / 6
              text: modelData + "x"
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              selected: displayTab.selectedDisplay && Number(displayTab.selectedDisplay.scale) === modelData
              foreground: Color.popups.text
              onClicked: {
                if (!displayTab.service || !displayTab.selectedDisplay || displayTab.service.state !== "idle") return
                displayTab.service.setDisplayValue(displayTab.selectedDisplay.name, "scale", modelData)
                displayTab.service.previewLayout()
              }
            }
          }
        }
        Item { width: 1; height: Style.spacing.sm }
        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

        Item {
          width: parent.width
          height: Style.space(30)
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "RESOLUTION · REFRESH"
            foreground: Color.popups.text
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.selectedDisplay ? displayTab.selectedDisplay.name : ""
            color: Qt.darker(Color.popups.text, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Row {
          width: parent.width - Style.spacing.md * 2
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.sm
          Ui.Dropdown {
            width: (parent.width - parent.spacing) / 2
            showLabel: false
            value: displayTab.selectedDisplay && Model.parseMode(displayTab.selectedDisplay.mode)
              ? Model.parseMode(displayTab.selectedDisplay.mode).width + "x"
                + Model.parseMode(displayTab.selectedDisplay.mode).height : ""
            options: displayTab.selectedDisplay
              ? Model.resolutionChoices(displayTab.selectedDisplay.availableModes) : []
            foreground: Color.popups.text
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
            foreground: Color.popups.text
            onChanged: function(value) {
              if (!displayTab.service || !displayTab.selectedDisplay || displayTab.service.state !== "idle") return
              displayTab.service.setDisplayValue(displayTab.selectedDisplay.name, "mode", value)
              displayTab.service.previewLayout()
            }
          }
        }
        Item { width: 1; height: Style.spacing.sm }
        Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }

        Item {
          width: parent.width
          height: Style.space(30)
          Ui.PanelSectionHeader {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "ROLE"
            foreground: Color.popups.text
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: displayTab.selectedDisplay ? displayTab.selectedDisplay.name : ""
            color: Qt.darker(Color.popups.text, 1.35)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        Grid {
          id: roleGrid
          width: parent.width - Style.spacing.md * 2
          anchors.horizontalCenter: parent.horizontalCenter
          columns: 3
          spacing: Style.spacing.xs
          Repeater {
            model: ["Primary", "Secondary", "Third"]
            delegate: Ui.Button {
              required property int index
              required property string modelData
              visible: displayTab.service
                && index < displayTab.service.displayDraft.filter(function(display) { return display.enabled }).length
              width: (roleGrid.width - roleGrid.spacing * 2) / 3
              text: modelData
              fontSize: Style.font.caption
              horizontalPadding: 0
              bordered: true
              selected: displayTab.selectedDisplay
                && displayTab.service.roleOf(displayTab.selectedDisplay.name) === index
              foreground: Color.popups.text
              onClicked: if (displayTab.service && displayTab.selectedDisplay && displayTab.service.state === "idle")
                displayTab.service.swapRole(displayTab.selectedDisplay.name, index)
            }
          }
        }
        Text {
          width: parent.width - Style.spacing.md * 2
          x: Style.spacing.md
          topPadding: Style.spacing.sm
          text: displayTab.selectedDisplay && displayTab.selectedDisplay.enabled
            ? "Lane " + displayTab.selectedDisplay.lane : "Enable this display to assign a role"
          color: Qt.darker(Color.popups.text, 1.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Item { width: 1; height: Style.spacing.sm }
      }
    }

    Item {
      visible: displayTab.service && displayTab.service.layoutError !== ""
        && displayTab.service.state !== "previewing"
      width: parent.width
      height: visible ? errorText.implicitHeight + Style.spacing.sm * 2 : 0
      Ui.PanelSeparator { width: parent.width; foreground: Color.urgent }
      Text {
        id: errorText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.md
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: displayTab.service ? displayTab.service.layoutError : ""
        wrapMode: Text.WordWrap
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      visible: displayTab.service && displayTab.service.state === "previewing"
      width: parent.width
      height: visible ? Style.space(46) : 0
      Ui.PanelSeparator { width: parent.width; foreground: Color.popups.text }
      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.md
        anchors.right: revertButton.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        text: "Keep these settings? Reverting in "
          + (displayTab.service ? displayTab.service.previewSeconds : 0) + " s"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Ui.Button {
        id: keepButton
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: "Keep"
        selected: true
        bordered: true
        foreground: Color.popups.text
        onClicked: displayTab.service.keepPreview()
      }
      Ui.Button {
        id: revertButton
        anchors.right: keepButton.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        text: "Revert"
        bordered: true
        foreground: Color.popups.text
        onClicked: displayTab.service.revertPreview("")
      }
    }
  }
}
