import QtQuick
import qs.Ui as Ui
import qs.Commons

Column {
  id: settingsTab
  required property var panelRoot
  readonly property real inset: panelRoot.regionPadH
  spacing: 0
  onVisibleChanged: if (visible && panelRoot && panelRoot.service)
    panelRoot.service.acquireStockLeases()

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
      anchors.leftMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - settingsTab.panelRoot.space6 - toggleSwitch.width
      text: parent.label
      elide: Text.ElideRight
      color: settingsTab.panelRoot.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Ui.ToggleSwitch {
      id: toggleSwitch
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      trackHeight: Style.spacing.controlHeight
      checked: parent.checked
      foreground: settingsTab.panelRoot.textPrimary
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
    label: "Hide Omarchy's workspace indicator"
    checked: settingsTab.panelRoot.service && settingsTab.panelRoot.service.config.hideNative
    onClicked: if (settingsTab.panelRoot.service)
      settingsTab.panelRoot.service.setSetting("hideNative", !checked)
  }
  Item { width: 1; height: settingsTab.panelRoot.space2 }
  Ui.PanelSeparator {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    foreground: Color.popups.text
  }

  PlainToggleRow {
    label: "Hide Omarchy's Display icon"
    checked: settingsTab.panelRoot.service && (settingsTab.panelRoot.service.config.hideDisplay
      || settingsTab.panelRoot.service.displayWidgetEnabled === false)
    onClicked: if (settingsTab.panelRoot.service)
      settingsTab.panelRoot.service.setSetting("hideDisplay", !checked)
  }
  Item { width: 1; height: settingsTab.panelRoot.space2 }
  Ui.PanelSeparator {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    foreground: Color.popups.text
  }

  PlainToggleRow {
    label: "Follow focus (keep monitors on the same station)"
    checked: settingsTab.panelRoot.service && settingsTab.panelRoot.service.config.followFocus
    onClicked: if (settingsTab.panelRoot.service)
      settingsTab.panelRoot.service.setSetting("followFocus", !checked)
  }
  Item { width: 1; height: settingsTab.panelRoot.space2 }
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
      anchors.leftMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - settingsTab.panelRoot.space6 - panelPositionValue.width
      text: "Panel opening position"
      elide: Text.ElideRight
      color: settingsTab.panelRoot.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Ui.Dropdown {
      id: panelPositionValue
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(130)
      showLabel: false
      value: settingsTab.panelRoot.service ? settingsTab.panelRoot.service.config.panelPosition : "left"
      options: [{ value: "left", label: "Left" }, { value: "center", label: "Center" }]
      foreground: settingsTab.panelRoot.textPrimary
      onChanged: function(value) {
        if (settingsTab.panelRoot.service) settingsTab.panelRoot.service.setSetting("panelPosition", value)
      }
    }
  }
  Item { width: 1; height: settingsTab.panelRoot.space2 }
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
      anchors.leftMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - settingsTab.panelRoot.space6 - graceValue.width
      text: "Grace delay before merging windows after unplug"
      elide: Text.ElideRight
      color: settingsTab.panelRoot.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Ui.Dropdown {
      id: graceValue
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(130)
      showLabel: false
      value: settingsTab.panelRoot.service ? String(settingsTab.panelRoot.service.config.graceMs) : "5000"
      options: [{ value: "0", label: "No delay" }, { value: "3000", label: "3 seconds" },
        { value: "5000", label: "5 seconds" }, { value: "10000", label: "10 seconds" }]
      foreground: settingsTab.panelRoot.textPrimary
      onChanged: function(value) {
        if (settingsTab.panelRoot.service) settingsTab.panelRoot.service.setSetting("graceMs", Number(value))
      }
    }
  }
  Item { width: 1; height: settingsTab.panelRoot.space2 }
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
      anchors.leftMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - settingsTab.panelRoot.space6 - stationsValue.width
      text: "Minimum stations"
      elide: Text.ElideRight
      color: settingsTab.panelRoot.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Ui.Dropdown {
      id: stationsValue
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(130)
      showLabel: false
      value: settingsTab.panelRoot.service ? String(settingsTab.panelRoot.service.config.minStations) : "3"
      options: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
      foreground: settingsTab.panelRoot.textPrimary
      onChanged: function(value) {
        if (settingsTab.panelRoot.service) settingsTab.panelRoot.service.setSetting("minStations", Number(value))
      }
    }
  }
  Item { width: 1; height: settingsTab.panelRoot.space2 }
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
      anchors.leftMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      text: "Installed version"
      color: settingsTab.panelRoot.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Item {
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      width: githubLink.implicitWidth + settingsTab.panelRoot.space1 + versionLabel.implicitWidth
      height: Math.max(githubLink.implicitHeight, versionLabel.implicitHeight)
      Ui.PanelActionButton {
        id: githubLink
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uf09b"
        fontSize: Style.font.iconLarge
        tooltipText: "Open Station on GitHub"
        foreground: settingsTab.panelRoot.textDim
        hoverColor: settingsTab.panelRoot.textPrimary
        focusable: true
        onClicked: Qt.openUrlExternally("https://github.com/Yakumy/Station")
      }
      Text {
        id: versionLabel
        anchors.left: githubLink.right
        anchors.leftMargin: settingsTab.panelRoot.space1
        anchors.verticalCenter: parent.verticalCenter
        text: "v" + settingsTab.panelRoot.pluginVersion
        color: settingsTab.panelRoot.textDim
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Item { width: 1; height: settingsTab.inset }
}
