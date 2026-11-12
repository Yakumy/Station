import QtQuick
import qs.Ui as Ui
import "." as PanelUi
import qs.Commons

Column {
  id: settingsTab
  required property var tokens
  required property string pluginVersion
  required property var service
  readonly property real inset: tokens.regionPadH
  spacing: 0
  onVisibleChanged: if (visible && tokens && service)
    service.acquireStockLeases()

  component PlainToggleRow: Item {
    property string label: ""
    property bool checked: false
    signal clicked()

    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(74)
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()

    PanelUi.ControlLabel {
      width: parent.width - settingsTab.tokens.space2 * 2
      text: parent.label
      elide: Text.ElideRight
    }
    Ui.ToggleSwitch {
      id: toggleSwitch
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.tokens.space3
      anchors.verticalCenter: parent.verticalCenter
      trackHeight: Style.spacing.controlHeight
      checked: parent.checked
      foreground: settingsTab.tokens.textPrimary
      interactive: false
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }

  Item { width: 1; height: settingsTab.inset }

  PlainToggleRow {
    objectName: "omarchyIndicatorToggle"
    label: "Show Omarchy default workspace indicator"
    checked: !!settingsTab.service && !settingsTab.service.config.hideNative
      && settingsTab.service.workspaceWidgetEnabled !== false
    onClicked: if (settingsTab.service)
      settingsTab.service.setSetting("hideNative", checked)
  }
  Item { width: 1; height: settingsTab.tokens.space2 }
  Ui.PanelSeparator {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    foreground: Color.popups.text
  }

  PlainToggleRow {
    label: "Show Omarchy Display Icon"
    checked: !!settingsTab.service && !settingsTab.service.config.hideDisplay
      && settingsTab.service.displayWidgetEnabled !== false
    onClicked: if (settingsTab.service)
      settingsTab.service.setSetting("hideDisplay", checked)
  }
  Item { width: 1; height: settingsTab.tokens.space2 }
  Ui.PanelSeparator {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    foreground: Color.popups.text
  }

  PlainToggleRow {
    label: "Follow focus (keep monitors on the same station)"
    checked: settingsTab.service && settingsTab.service.config.followFocus
    onClicked: if (settingsTab.service)
      settingsTab.service.setSetting("followFocus", !checked)
  }
  Item { width: 1; height: settingsTab.tokens.space2 }
  Ui.PanelSeparator {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    foreground: Color.popups.text
  }

  Item {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(74)
    PanelUi.ControlLabel {
      width: parent.width - settingsTab.tokens.space2 * 2
      anchors.leftMargin: panelPositionValue.x
      text: "Panel opening position"
      elide: Text.ElideRight
    }
    Ui.Dropdown {
      id: panelPositionValue
      anchors.right: parent.right
      anchors.left: parent.left
      anchors.leftMargin: (parent.width - Math.min(parent.width - settingsTab.tokens.space2 * 2, (parent.width - settingsTab.inset * 2) * 1.2) * 0.96) / 2
      anchors.rightMargin: anchors.leftMargin
      anchors.verticalCenter: parent.verticalCenter
      showLabel: false
      value: settingsTab.service ? settingsTab.service.config.panelPosition : "left"
      options: [{ value: "left", label: "Bar" }, { value: "center", label: "Center" }]
      foreground: settingsTab.tokens.textPrimary
      onChanged: function(value) {
        if (settingsTab.service) settingsTab.service.setSetting("panelPosition", value)
      }
    }
  }
  Item { width: 1; height: settingsTab.tokens.space2 }
  Ui.PanelSeparator {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    foreground: Color.popups.text
  }

  Item {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(74)
    PanelUi.ControlLabel {
      text: "Installed version"
    }
    Item {
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.tokens.space3
      anchors.verticalCenter: parent.verticalCenter
      width: githubLink.implicitWidth + settingsTab.tokens.space1 + versionLabel.implicitWidth
      height: Math.max(githubLink.implicitHeight, versionLabel.implicitHeight)
      Ui.PanelActionButton {
        id: githubLink
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uf09b"
        fontSize: Style.font.iconLarge
        tooltipText: "Open Station on GitHub"
        foreground: settingsTab.tokens.textDim
        hoverColor: settingsTab.tokens.textPrimary
        focusable: true
        onClicked: Qt.openUrlExternally("https://github.com/Yakumy/Station")
      }
      Text {
        id: versionLabel
        anchors.left: githubLink.right
        anchors.leftMargin: settingsTab.tokens.space1
        anchors.verticalCenter: parent.verticalCenter
        text: settingsTab.pluginVersion ? "v" + settingsTab.pluginVersion : "unknown"
        color: settingsTab.tokens.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Item { width: 1; height: settingsTab.inset }
}
