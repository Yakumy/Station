import QtQuick
import qs.Ui as Ui
import "." as PanelUi
import qs.Commons

Column {
  id: settingsTab
  required property var tokens
  required property string pluginVersion
  required property var service
  property bool narrow: false
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
    height: Style.space(48)
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()

    Text {
      anchors.left: parent.left
      anchors.leftMargin: settingsTab.tokens.space3
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - settingsTab.tokens.space6 - toggleSwitch.width
      text: parent.label
      elide: Text.ElideRight
      color: settingsTab.tokens.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    PanelUi.ToggleSwitch {
      id: toggleSwitch
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.tokens.space3
      anchors.verticalCenter: parent.verticalCenter
      checked: parent.checked
      interactive: false
      sizeFactor: settingsTab.narrow ? 0.7 : 1
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

  Item {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(48)
    Text {
      anchors.left: parent.left
      anchors.leftMargin: settingsTab.tokens.space3
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - settingsTab.tokens.space6 - panelPositionValue.width
      text: "Panel opening position"
      elide: Text.ElideRight
      color: settingsTab.tokens.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    // The current style name sets the width, so it is never elided, while
    // Bar portrait keeps the base width and the row label stays whole.
    TextMetrics {
      id: currentPosition
      text: panelPositionValue.currentLabel()
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Ui.Dropdown {
      id: panelPositionValue
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.tokens.space3
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(130) * 0.99, Math.ceil(currentPosition.advanceWidth)
        + Style.spacing.controlPaddingX + Style.spacing.md + Style.spacing.controlGap + Style.space(20))
      showLabel: false
      value: settingsTab.service ? settingsTab.service.config.panelPosition : "bar-landscape"
      options: [
        { value: "bar-landscape", label: "Bar landscape" },
        { value: "bar-portrait", label: "Bar portrait" },
        { value: "center-landscape", label: "Center landscape" }
      ]
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
    height: Style.space(48)
    Text {
      anchors.left: parent.left
      anchors.leftMargin: settingsTab.tokens.space3
      anchors.verticalCenter: parent.verticalCenter
      text: "Installed version"
      color: settingsTab.tokens.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
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
