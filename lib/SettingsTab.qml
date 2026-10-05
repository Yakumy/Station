import QtQuick
import qs.Ui as Ui
import qs.Commons

Column {
  id: settingsTab
  required property var panelRoot
  readonly property real inset: Style.spacing.md
  spacing: Style.spacing.sm

  Item { width: 1; height: Math.max(0, settingsTab.inset - settingsTab.spacing) }

  Ui.Toggle {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    label: "Hide Omarchy's workspace indicator"
    checked: settingsTab.panelRoot.service && settingsTab.panelRoot.service.config.hideNative
    foreground: Color.popups.text
    onClicked: if (settingsTab.panelRoot.service)
      settingsTab.panelRoot.service.setSetting("hideNative", !checked)
  }
  Ui.Toggle {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    label: "Follow focus (keep monitors on the same station)"
    checked: settingsTab.panelRoot.service && settingsTab.panelRoot.service.config.followFocus
    foreground: Color.popups.text
    onClicked: if (settingsTab.panelRoot.service)
      settingsTab.panelRoot.service.setSetting("followFocus", !checked)
  }
  Ui.BorderSurface {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(50)
    color: "transparent"
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
    radius: Style.cornerRadius
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: "Grace delay before merging windows after unplug"
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Ui.Dropdown {
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(130)
      showLabel: false
      value: settingsTab.panelRoot.service ? String(settingsTab.panelRoot.service.config.graceMs) : "5000"
      options: [{ value: "0", label: "No delay" }, { value: "3000", label: "3 seconds" },
        { value: "5000", label: "5 seconds" }, { value: "10000", label: "10 seconds" }]
      foreground: Color.popups.text
      onChanged: function(value) {
        if (settingsTab.panelRoot.service) settingsTab.panelRoot.service.setSetting("graceMs", Number(value))
      }
    }
  }
  Ui.BorderSurface {
    width: settingsTab.width - settingsTab.inset * 2
    x: settingsTab.inset
    height: Style.space(50)
    color: "transparent"
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Style.normalBorderWidth)
    radius: Style.cornerRadius
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: "Minimum stations"
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Ui.Dropdown {
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(130)
      showLabel: false
      value: settingsTab.panelRoot.service ? String(settingsTab.panelRoot.service.config.minStations) : "3"
      options: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"]
      foreground: Color.popups.text
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
    radius: Style.cornerRadius
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: "Installed version"
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      text: "2.0.0"
      color: Qt.darker(Color.popups.text, 1.35)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Item { width: 1; height: Math.max(0, settingsTab.inset - settingsTab.spacing) }
}
