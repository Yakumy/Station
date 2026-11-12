import QtQuick
import "Binds.js" as Binds
import qs.Ui as Ui
import qs.Commons
import "." as Keys
import "../panel" as PanelUi

Column {
  id: keybindingsTab
  required property var tokens
  required property var service
  property bool active: false
  property string editingBindingId: ""
  property var editingModifiers: ({ SUPER: false, CTRL: false, ALT: false, SHIFT: false })
  property string editingKey: ""
  readonly property var bindingGroups: [
    { label: "Switch to station", combo: "SUPER + 1 … 0", ids: keybindingsTab.bindingIds("switch-", 10) },
    { label: "Move window to station", combo: "SUPER + SHIFT + 1 … 0", ids: keybindingsTab.bindingIds("send-", 10) },
    { label: "Move silently (no follow)", combo: "SUPER + SHIFT + ALT + 1 … 0", ids: keybindingsTab.bindingIds("silent-", 10) },
    { label: "Station to the left", combo: "SUPER + CTRL + ←", ids: ["go-left"] },
    { label: "Station to the right", combo: "SUPER + CTRL + →", ids: ["go-right"] },
    { label: "Station above", combo: "SUPER + CTRL + ↑", ids: ["go-up"] },
    { label: "Station below", combo: "SUPER + CTRL + ↓", ids: ["go-down"] },
    { label: "Move across monitors and stations", combo: "SUPER + SHIFT + CTRL + ← → ↑ ↓",
      ids: ["shift-left", "shift-right", "shift-up", "shift-down"] }
  ]

  function bindingIds(prefix, count) {
    var ids = []
    for (var i = 1; i <= count; i++) ids.push(prefix + i)
    return ids
  }

  function bindingForId(id) {
    if (!service) return null
    for (var i = 0; i < service.bindStatuses.length; i++)
      if (service.bindStatuses[i].id === id) return service.bindStatuses[i]
    return null
  }

  function conflictsFor(ids) {
    var conflicts = []
    for (var i = 0; i < ids.length; i++) {
      var binding = bindingForId(ids[i])
      if (binding && binding.status === "conflict") conflicts.push(binding)
    }
    return conflicts
  }

  function groupStatus(ids) {
    var priority = { conflict: 4, unverified: 3, replacement: 2, free: 1 }
    var result = "free", score = 0
    for (var i = 0; i < ids.length; i++) {
      var binding = bindingForId(ids[i])
      var status = binding ? binding.status : "unverified"
      if ((priority[status] || 0) > score) { result = status; score = priority[status] || 0 }
    }
    return result
  }

  function statusLabel(status) {
    return status === "replacement" ? "REPLACES DEFAULT" : String(status || "unverified").toUpperCase()
  }

  function beginBindingEdit(binding) {
    var normalized = Binds.normalize(binding.combo).split("+")
    editingModifiers = {
      SUPER: normalized.indexOf("SUPER") !== -1,
      CTRL: normalized.indexOf("CTRL") !== -1,
      ALT: normalized.indexOf("ALT") !== -1,
      SHIFT: normalized.indexOf("SHIFT") !== -1
    }
    editingKey = normalized[normalized.length - 1] || ""
    editingBindingId = binding.id
  }

  function toggleEditingModifier(name) {
    var next = Object.assign({}, editingModifiers)
    next[name] = !next[name]
    editingModifiers = next
  }

  function applyBindingEdit() {
    if (!service || !editingBindingId || !editingKey.trim()) return
    var parts = []
    ;["SUPER", "CTRL", "ALT", "SHIFT"].forEach(function(mod) {
      if (editingModifiers[mod]) parts.push(mod)
    })
    parts.push(editingKey.trim())
    if (service.setBinding(editingBindingId, parts.join(" + ")) === "ok") editingBindingId = ""
  }
  readonly property real inset: tokens.regionPadH
  spacing: 0

  Item { width: 1; height: keybindingsTab.inset }

  Repeater {
    model: keybindingsTab.bindingGroups
    delegate: Column {
      id: bindingGroup
      required property var modelData
      required property int index
      width: keybindingsTab.width - keybindingsTab.inset * 2
      x: keybindingsTab.inset
      property string groupState: keybindingsTab.groupStatus(modelData.ids)
      readonly property bool hasSeparator: index < keybindingsTab.bindingGroups.length - 1

      Item {
        width: parent.width
        height: Style.space(74)
        PanelUi.ControlLabel {
          width: parent.width - keybindingsTab.tokens.space2 * 2
          text: bindingGroup.modelData.label
        }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: keybindingsTab.inset
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.65
          horizontalAlignment: Text.AlignLeft
          text: bindingGroup.modelData.combo
          elide: Text.ElideRight
          // The combo is this row's value, so it carries the emphasis weight.
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.Normal
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: keybindingsTab.tokens.space3
          anchors.verticalCenter: parent.verticalCenter
          text: keybindingsTab.statusLabel(bindingGroup.groupState)
          color: bindingGroup.groupState === "conflict" ? Color.urgent
            : (bindingGroup.groupState === "replacement" ? Color.accent
              : Qt.darker(Color.popups.text, 1.4))
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.weight: bindingGroup.groupState === "conflict" ? Font.DemiBold : Font.Medium
        }
      }

      Repeater {
        model: keybindingsTab.conflictsFor(bindingGroup.modelData.ids)
        delegate: Ui.BorderSurface {
          id: conflictRow
          required property var modelData
          width: bindingGroup.width
          height: conflictContent.implicitHeight + keybindingsTab.tokens.space3 * 2
          color: Color.menu.selectedBackground
          borderSpec: Border.flat(Color.urgent, Style.normalBorderWidth)
          radius: Style.cornerRadius
          Column {
            id: conflictContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: keybindingsTab.tokens.space3
            anchors.rightMargin: keybindingsTab.tokens.space3
            spacing: keybindingsTab.tokens.space2
            Text {
              width: parent.width
              text: conflictRow.modelData.combo + " is used by " + conflictRow.modelData.owners.join(", ")
              wrapMode: Text.WordWrap
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            Row {
              spacing: keybindingsTab.tokens.space2
              PanelUi.ActionButton {
                text: "Pick another key"
                bordered: true
                foreground: Color.popups.text
                onClicked: keybindingsTab.beginBindingEdit(conflictRow.modelData)
              }
              PanelUi.ActionButton {
                text: "Replace and unbind it"
                accent: Color.urgent
                background: Color.urgent
                foreground: Color.popups.background
                onClicked: keybindingsTab.service.approveBinding(conflictRow.modelData.combo)
              }
            }
            Flow {
              width: parent.width
              visible: keybindingsTab.editingBindingId === conflictRow.modelData.id
              spacing: keybindingsTab.tokens.space1
              Repeater {
                model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                delegate: PanelUi.ChoiceChip {
                  required property string modelData
                  text: modelData
                  selected: !!keybindingsTab.editingModifiers[modelData]
                  onClicked: keybindingsTab.toggleEditingModifier(modelData)
                }
              }
              Keys.BindingKeyPicker {
                value: keybindingsTab.editingKey
                available: keybindingsTab.active
                onPicked: function(key) { keybindingsTab.editingKey = key }
              }
              PanelUi.ActionButton {
                text: "Apply"
                accent: Color.accent
                background: Color.accent
                foreground: Color.popups.background
                onClicked: keybindingsTab.applyBindingEdit()
              }
              PanelUi.ActionButton {
                text: "Cancel"
                bordered: true
                foreground: Color.popups.text
                onClicked: keybindingsTab.editingBindingId = ""
              }
            }
          }
        }
      }

      Item {
        visible: bindingGroup.hasSeparator
        width: parent.width
        height: keybindingsTab.tokens.space2
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
