import QtQuick
import qs.Ui as Ui
import qs.Commons

Column {
  id: keybindingsTab
  required property var panelRoot
  readonly property real inset: Style.spacing.md
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
        radius: Style.cornerRadius
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.36
          text: bindingGroup.modelData.label
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.39
          horizontalAlignment: Text.AlignHCenter
          text: bindingGroup.modelData.combo
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          text: keybindingsTab.panelRoot.statusLabel(bindingGroup.groupState)
          color: bindingGroup.groupState === "conflict" ? Color.urgent
            : (bindingGroup.groupState === "replacement" ? Color.accent : Qt.darker(Color.popups.text, 1.35))
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: bindingGroup.groupState === "conflict"
        }
      }

      Repeater {
        model: keybindingsTab.panelRoot.conflictsFor(bindingGroup.modelData.ids)
        delegate: Ui.BorderSurface {
          id: conflictRow
          required property var modelData
          width: bindingGroup.width
          height: conflictContent.implicitHeight + Style.spacing.md * 2
          color: Color.menu.selectedBackground
          borderSpec: Border.surfaceSpec("menu", "border", Color.urgent, Style.normalBorderWidth)
          radius: Style.cornerRadius
          Column {
            id: conflictContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.md
            spacing: Style.spacing.sm
            Text {
              width: parent.width
              text: conflictRow.modelData.combo + " is used by " + conflictRow.modelData.owners.join(", ")
              wrapMode: Text.WordWrap
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Row {
              spacing: Style.spacing.sm
              Ui.Button {
                text: "Pick another key"
                bordered: true
                foreground: Color.popups.text
                onClicked: keybindingsTab.panelRoot.beginBindingEdit(conflictRow.modelData)
              }
              Ui.Button {
                text: "Replace and unbind it"
                selected: true
                bordered: true
                foreground: Color.popups.text
                accent: Color.urgent
                onClicked: keybindingsTab.panelRoot.service.approveBinding(conflictRow.modelData.combo)
              }
            }
            Row {
              visible: keybindingsTab.panelRoot.editingBindingId === conflictRow.modelData.id
              spacing: Style.spacing.xs
              Repeater {
                model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                delegate: Ui.Button {
                  required property string modelData
                  text: modelData
                  bordered: true
                  selected: !!keybindingsTab.panelRoot.editingModifiers[modelData]
                  foreground: Color.popups.text
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
                text: "Apply"
                selected: true
                bordered: true
                foreground: Color.popups.text
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
