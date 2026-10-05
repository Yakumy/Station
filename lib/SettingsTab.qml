import QtQuick
import qs.Ui as Ui
import qs.Commons

Column {
  id: settingsTab
  required property var panelRoot
  readonly property real inset: panelRoot.regionPadH
  spacing: panelRoot.space2

  Item { width: 1; height: Math.max(0, settingsTab.inset - settingsTab.spacing) }

  Ui.Toggle {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    label: "Hide Omarchy's workspace indicator"
    titleSize: Style.font.body
    checked: settingsTab.panelRoot.service && settingsTab.panelRoot.service.config.hideNative
    foreground: settingsTab.panelRoot.textPrimary
    onClicked: if (settingsTab.panelRoot.service)
      settingsTab.panelRoot.service.setSetting("hideNative", !checked)
  }
  Ui.Toggle {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    label: "Follow focus (keep monitors on the same station)"
    titleSize: Style.font.body
    checked: settingsTab.panelRoot.service && settingsTab.panelRoot.service.config.followFocus
    foreground: settingsTab.panelRoot.textPrimary
    onClicked: if (settingsTab.panelRoot.service)
      settingsTab.panelRoot.service.setSetting("followFocus", !checked)
  }
  Ui.BorderSurface {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(48)
    color: "transparent"
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
    radius: settingsTab.panelRoot.radiusMd
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
  Ui.BorderSurface {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(48)
    color: "transparent"
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
    radius: settingsTab.panelRoot.radiusMd
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
  Ui.BorderSurface {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(48)
    color: "transparent"
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
    radius: settingsTab.panelRoot.radiusMd
    Text {
      anchors.left: parent.left
      anchors.leftMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      text: "Installed version"
      color: settingsTab.panelRoot.textPrimary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: settingsTab.panelRoot.space3
      anchors.verticalCenter: parent.verticalCenter
      text: settingsTab.panelRoot.pluginVersion
      color: settingsTab.panelRoot.textDim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Item { width: 1; height: Math.max(0, settingsTab.inset - settingsTab.spacing) }
}
