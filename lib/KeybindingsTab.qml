import QtQuick
import qs.Ui as Ui
import qs.Commons
import "." as Station

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
      required property int index
      width: keybindingsTab.width - keybindingsTab.inset * 2
      x: keybindingsTab.inset
      property string groupState: keybindingsTab.panelRoot.groupStatus(modelData.ids)
      readonly property bool hasSeparator: index < keybindingsTab.panelRoot.bindingGroups.length - 1

      Item {
        width: parent.width
        height: Style.space(44)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: keybindingsTab.panelRoot.space3
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.36
          text: bindingGroup.modelData.label
          elide: Text.ElideRight
          color: Color.popups.text
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
          color: Color.popups.text
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
            : (bindingGroup.groupState === "replacement" ? Color.accent
              : Qt.darker(Color.popups.text, 1.4))
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
          borderSpec: Border.flat(Color.urgent, Style.normalBorderWidth)
          radius: Style.cornerRadius
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
                radius: Style.cornerRadius
                text: "Pick another key"
                bordered: true
                foreground: Color.popups.text
                onClicked: keybindingsTab.panelRoot.beginBindingEdit(conflictRow.modelData)
              }
              Ui.Button {
                height: keybindingsTab.panelRoot.controlHeight
                radius: Style.cornerRadius
                text: "Replace and unbind it"
                accent: Color.urgent
                background: Color.urgent
                foreground: Color.popups.background
                onClicked: keybindingsTab.panelRoot.service.approveBinding(conflictRow.modelData.combo)
              }
            }
            Row {
              visible: keybindingsTab.panelRoot.editingBindingId === conflictRow.modelData.id
              spacing: keybindingsTab.panelRoot.space1
              Repeater {
                model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                delegate: Station.ChoiceChip {
                  required property string modelData
                  text: modelData
                  selected: !!keybindingsTab.panelRoot.editingModifiers[modelData]
                  onClicked: keybindingsTab.panelRoot.toggleEditingModifier(modelData)
                }
              }
              Ui.TextField {
                width: Style.space(88)
                text: keybindingsTab.panelRoot.editingKey
                placeholderText: "KEY"
                foreground: Color.popups.text
                onTextChanged: if (activeFocus) keybindingsTab.panelRoot.editingKey = text
                onAccepted: keybindingsTab.panelRoot.applyBindingEdit()
              }
              Ui.Button {
                height: keybindingsTab.panelRoot.controlHeight
                radius: Style.cornerRadius
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

      Item {
        visible: bindingGroup.hasSeparator
        width: parent.width
        height: keybindingsTab.panelRoot.space2
      }
      Ui.PanelSeparator {
        visible: bindingGroup.hasSeparator
        width: parent.width
        foreground: Color.popups.text
      }
    }
  }

  Item { width: 1; height: keybindingsTab.inset }
}
