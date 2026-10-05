import QtQuick
import qs.Ui as Ui
import qs.Commons

Column {
  id: keybindingsTab
  required property var panelRoot
  readonly property real inset: panelRoot.regionPadH
  spacing: 0

  Item { width: 1; height: keybindingsTab.inset }

  Repeater {
    model: keybindingsTab.panelRoot.bindingGroups
    delegate: Column {
      id: bindingGroup
      required property var modelData
      width: keybindingsTab.width - keybindingsTab.inset * 2
      x: keybindingsTab.inset
      property string groupState: keybindingsTab.panelRoot.groupStatus(modelData.ids)

      Ui.BorderSurface {
        width: parent.width
        height: Style.space(44)
        color: "transparent"
        borderSpec: Border.surfaceSpec("popups", "border",
          bindingGroup.groupState === "conflict" ? Color.urgent : Color.popups.border,
          Style.normalBorderWidth)
        radius: keybindingsTab.panelRoot.radiusMd
        Text {
          anchors.left: parent.left
          anchors.leftMargin: keybindingsTab.panelRoot.space3
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.36
          text: bindingGroup.modelData.label
          elide: Text.ElideRight
          color: keybindingsTab.panelRoot.textPrimary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.39
          horizontalAlignment: Text.AlignHCenter
          text: bindingGroup.modelData.combo
          elide: Text.ElideRight
          // The combo is this row's value, so it carries the emphasis weight.
          color: keybindingsTab.panelRoot.textPrimary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: keybindingsTab.panelRoot.space3
          anchors.verticalCenter: parent.verticalCenter
          text: keybindingsTab.panelRoot.statusLabel(bindingGroup.groupState)
          color: bindingGroup.groupState === "conflict" ? Color.urgent
            : (bindingGroup.groupState === "replacement" ? Color.accent : keybindingsTab.panelRoot.textDim)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: bindingGroup.groupState === "conflict" ? Font.DemiBold : Font.Medium
        }
      }

      Repeater {
        model: keybindingsTab.panelRoot.conflictsFor(bindingGroup.modelData.ids)
        delegate: Ui.BorderSurface {
          id: conflictRow
          required property var modelData
          width: bindingGroup.width
          height: conflictContent.implicitHeight + keybindingsTab.panelRoot.space3 * 2
          color: Color.menu.selectedBackground
          borderSpec: Border.surfaceSpec("menu", "border", Color.urgent, Style.normalBorderWidth)
          radius: keybindingsTab.panelRoot.radiusMd
          Column {
            id: conflictContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: keybindingsTab.panelRoot.space3
            anchors.rightMargin: keybindingsTab.panelRoot.space3
            spacing: keybindingsTab.panelRoot.space2
            Text {
              width: parent.width
              text: conflictRow.modelData.combo + " is used by " + conflictRow.modelData.owners.join(", ")
              wrapMode: Text.WordWrap
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Row {
              spacing: keybindingsTab.panelRoot.space2
              Ui.Button {
                height: keybindingsTab.panelRoot.controlHeight
                radius: keybindingsTab.panelRoot.radiusSm
                text: "Pick another key"
                bordered: true
                foreground: keybindingsTab.panelRoot.textPrimary
                onClicked: keybindingsTab.panelRoot.beginBindingEdit(conflictRow.modelData)
              }
              Ui.Button {
                height: keybindingsTab.panelRoot.controlHeight
                radius: keybindingsTab.panelRoot.radiusSm
                text: "Replace and unbind it"
                bordered: true
                accent: Color.urgent
                foreground: keybindingsTab.panelRoot.textPrimary
                onClicked: keybindingsTab.panelRoot.service.approveBinding(conflictRow.modelData.combo)
              }
            }
            Row {
              visible: keybindingsTab.panelRoot.editingBindingId === conflictRow.modelData.id
              spacing: keybindingsTab.panelRoot.space1
              Repeater {
                model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                delegate: Ui.Button {
                  required property string modelData
                  height: keybindingsTab.panelRoot.controlHeight
                  radius: keybindingsTab.panelRoot.radiusSm
                  text: modelData
                  bordered: true
                  selected: !!keybindingsTab.panelRoot.editingModifiers[modelData]
                  foreground: keybindingsTab.panelRoot.textPrimary
                  onClicked: keybindingsTab.panelRoot.toggleEditingModifier(modelData)
                }
              }
              Ui.TextField {
                width: Style.space(88)
                text: keybindingsTab.panelRoot.editingKey
                placeholderText: "KEY"
                foreground: keybindingsTab.panelRoot.textPrimary
                onTextChanged: if (activeFocus) keybindingsTab.panelRoot.editingKey = text
                onAccepted: keybindingsTab.panelRoot.applyBindingEdit()
              }
              Ui.Button {
                height: keybindingsTab.panelRoot.controlHeight
                radius: keybindingsTab.panelRoot.radiusSm
                text: "Apply"
                accent: Color.accent
                background: Color.accent
                foreground: Color.popups.background
                onClicked: keybindingsTab.panelRoot.applyBindingEdit()
              }
            }
          }
        }
      }
    }
  }

  Item { width: 1; height: keybindingsTab.inset }
}
