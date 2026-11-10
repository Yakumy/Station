import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "Grid.js" as Grid
import "." as Stations

// Workspace mode, each monitor's workspaces, bar indicator style, compact mode and
// open apps. Edits stay in a draft that the layout previews; Apply sends it in one
// call, and the migration commits a changed map. Cancel returns to the saved values.
Column {
  id: root
  required property var tokens
  required property var service
  readonly property real pad: tokens.regionPadH
  readonly property var config: service ? service.config : ({})
  readonly property var outputs: service && service.workspaceTarget ? service.workspaceTarget.outputs || [] : []
  readonly property bool idle: !!service && service.state === "idle"
  // The modes differ only across monitors, so one monitor locks the selector.
  readonly property bool singleOutput: outputs.length <= 1
  readonly property int rowCount: 4

  function savedValues() {
    return JSON.parse(JSON.stringify({
      workspaceMode: Grid.MODES.indexOf(config.workspaceMode) !== -1 ? config.workspaceMode : "station",
      workspaceLayout: config.workspaceLayout || { repetitive: {}, nonrepetitive: {} },
      indicatorStyle: config.indicatorStyle || "prefixed",
      compactMode: config.compactMode || "hover",
      showOpenApps: config.showOpenApps !== false
    }))
  }
  // What the user sees: the mode, the numbers each monitor gets in both per-monitor
  // modes, and the bar options. Layout entries that change nothing do not count.
  function effective(values) {
    return JSON.stringify([values.workspaceMode, values.indicatorStyle, values.compactMode, values.showOpenApps,
      Grid.assigned("repetitive", outputs, values.workspaceLayout),
      Grid.assigned("nonrepetitive", outputs, values.workspaceLayout)])
  }
  property var base: savedValues()
  property var draft: savedValues()
  property string notice: ""
  readonly property bool dirty: effective(draft) !== effective(base)
  readonly property string savedKey: JSON.stringify(savedValues())
  readonly property string mode: draft.workspaceMode
  readonly property var assigned: Grid.assigned(mode, outputs, draft.workspaceLayout)
  onSavedKeyChanged: if (!dirty) reset()
  onModeChanged: notice = ""

  function reset() {
    base = savedValues()
    draft = savedValues()
    notice = ""
  }
  function edit(change) {
    draft = Object.assign(JSON.parse(JSON.stringify(draft)), change)
    notice = ""
  }
  function layoutWith(name, lists) {
    var layout = JSON.parse(JSON.stringify(draft.workspaceLayout))
    if (name === "repetitive") outputs.forEach(function(output, index) { layout.repetitive[output] = lists[index].length })
    else outputs.forEach(function(output, index) { layout.nonrepetitive[output] = lists[index] })
    return layout
  }

  // Repetitive: every monitor has its own count, 1 to 10. Non-repetitive: only the
  // last monitor has − and +. + adds the next number to it, − removes the highest
  // number while its monitor keeps one.
  function stepState(output) {
    var index = outputs.indexOf(output)
    var none = { shown: false, down: false, up: false }
    if (index === -1 || mode === "station") return none
    if (mode === "repetitive") {
      var count = assigned[index].length
      return { shown: true, down: count > 1, up: count < Grid.MAX_STATIONS }
    }
    if (index !== outputs.length - 1) return none
    var total = assigned.reduce(function(sum, row) { return sum + row.length }, 0)
    var holder = assigned.filter(function(row) { return row.indexOf(total) !== -1 })[0]
    return { shown: true, down: !!holder && holder.length > 1,
      up: total < Grid.MAX_GLOBAL && assigned[index].length < Grid.MAX_STATIONS }
  }
  function changeCount(output, delta) {
    var index = outputs.indexOf(output)
    var state = stepState(output)
    if (!state.shown || (delta < 0 && !state.down) || (delta > 0 && !state.up)) return
    var lists = assigned.map(function(row) { return row.slice() })
    if (mode === "repetitive") {
      if (delta > 0) lists[index].push(lists[index].length + 1)
      else lists[index].pop()
    } else {
      var total = lists.reduce(function(sum, row) { return sum + row.length }, 0)
      if (delta > 0) lists[index].push(total + 1)
      else lists.forEach(function(row) { var at = row.indexOf(total); if (at !== -1) row.splice(at, 1) })
    }
    edit({ workspaceLayout: layoutWith(mode, lists) })
  }
  // Non-repetitive only: give a number to another monitor. Each monitor keeps at
  // least one and holds at most ten.
  function moveWorkspace(number, output) {
    var to = outputs.indexOf(output)
    if (mode !== "nonrepetitive" || to === -1) return
    var lists = assigned.map(function(row) { return row.slice() })
    var from = -1
    lists.forEach(function(row, index) { if (row.indexOf(number) !== -1) from = index })
    if (from === -1 || from === to || lists[from].length <= 1 || lists[to].length >= Grid.MAX_STATIONS) return
    lists[from].splice(lists[from].indexOf(number), 1)
    lists[to].push(number)
    lists[to].sort(function(a, b) { return a - b })
    edit({ workspaceLayout: layoutWith(mode, lists) })
  }
  function apply() {
    if (!service || !dirty) return
    var result = service.setSetting("workspaces", JSON.parse(JSON.stringify(draft)))
    if (result === "ok") base = JSON.parse(JSON.stringify(draft))
    else notice = result === "busy" ? "Station is busy. Try again in a moment." : "These settings could not be applied."
  }

  component Caption: Text {
    color: root.tokens.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  // A row's message sits in its bottom-left corner, as in Displays.
  component RowMessage: Caption {
    anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
    anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
    anchors.bottom: parent.bottom; anchors.bottomMargin: root.tokens.space1
    visible: text !== ""
    elide: Text.ElideRight
  }
  component RowLabel: Text {
    color: root.tokens.textPrimary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }
  component ModeSelector: Ui.BorderSurface {
    id: selector
    property string value: ""
    property var options: []
    signal changed(string value)
    opacity: enabled ? 1 : root.tokens.disabledOpacity
    color: Commons.Color.popups.background
    borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
    radius: Style.cornerRadius
    clip: true

    Row {
      anchors.fill: parent
      anchors.margins: Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Repeater {
        model: selector.options
        delegate: Item {
          required property var modelData
          required property int index
          width: (selector.width - Math.max(1, Style.normalBorderWidth) * 2) / selector.options.length
          height: parent.height
          Ui.Button {
            anchors.fill: parent
            topLeftRadius: index === 0 ? Style.cornerRadius : 0
            bottomLeftRadius: index === 0 ? Style.cornerRadius : 0
            topRightRadius: index === selector.options.length - 1 ? Style.cornerRadius : 0
            bottomRightRadius: index === selector.options.length - 1 ? Style.cornerRadius : 0
            objectName: "workspaceMode-" + modelData.value
            text: modelData.label
            selected: selector.enabled && selector.value === modelData.value
            focusable: true
            foreground: Commons.Color.popups.text
            background: Commons.Color.popups.background
            accent: Commons.Color.accent
            onClicked: selector.changed(modelData.value)
          }
          Rectangle {
            visible: index > 0
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Style.normalBorderWidth)
            color: Border.color(Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent))
          }
        }
      }
    }
  }

  Row {
    width: parent.width
    height: Style.space(428)
    Column {
      id: left
      width: parent.width * 0.576
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "LAYOUT"; foreground: Commons.Color.popups.text
        }
        Caption {
          anchors.right: parent.right; anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "SCROLL TO ZOOM"
        }
      }
      Stations.WorkspacesLayout {
        x: root.pad; width: parent.width - root.pad * 2; height: Style.space(370)
        service: root.service
        tokens: root.tokens
        outputs: root.outputs
        assigned: root.assigned
        mode: root.mode
        steps: root.outputs.map(function(output) { return root.stepState(output) })
        onCountChangeRequested: function(output, delta) { root.changeCount(output, delta) }
        onWorkspaceMoved: function(number, output) { root.moveWorkspace(number, output) }
      }
    }
    Rectangle {
      width: Math.max(1, Style.normalBorderWidth); height: parent.height
      color: Commons.Color.popups.text; opacity: 0.12
    }
    Column {
      width: parent.width - left.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          text: "WORKSPACES"; foreground: Commons.Color.popups.text
        }
      }
      Ui.BorderSurface {
        id: controlFrame
        width: parent.width - Style.space(28) * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius
        Column {
          anchors.fill: parent
          spacing: 0
          Item {
            width: parent.width; height: controlFrame.height / root.rowCount
            Caption {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.top: parent.top; anchors.topMargin: root.tokens.space2
              text: "MODE"
            }
            ModeSelector {
              objectName: "workspaceModeSelector"
              enabled: !root.singleOutput
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.controlHeight
              value: root.mode
              options: [{ value: "station", label: "Sync" }, { value: "repetitive", label: "Repetitive" },
                { value: "nonrepetitive", label: "Non-repetitive" }]
              onChanged: function(value) { root.edit({ workspaceMode: value }) }
            }
            RowMessage {
              objectName: "workspaceModeNote"
              text: root.singleOutput ? "Works only on multiple monitors"
                : root.mode === "nonrepetitive" ? "Drag workspaces onto a monitor to assign them" : ""
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / root.rowCount
            RowLabel {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: styleValue.left; anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              text: "Indicator style"
            }
            Ui.Dropdown {
              id: styleValue
              objectName: "indicatorStyleDropdown"
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(130)
              showLabel: false
              value: root.draft.indicatorStyle
              options: [
                { value: "prefixed", label: root.mode === "station" ? "S1 S2 S3" : "W1 W2 W3" },
                { value: "number", label: "1 2 3" },
                { value: "roman", label: "I II III" }
              ]
              foreground: root.tokens.textPrimary
              onChanged: function(value) { root.edit({ indicatorStyle: value }) }
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / root.rowCount
            RowLabel {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: compactValue.left; anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              text: "Compact mode"
            }
            RowMessage {
              objectName: "compactModeNote"
              text: root.draft.compactMode === "off" ? "Every workspace, the current one as a square"
                : root.draft.compactMode === "hover" ? "The current one, the rest on hover"
                : "Only the current one"
            }
            Ui.Dropdown {
              id: compactValue
              objectName: "compactModeDropdown"
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(130)
              showLabel: false
              value: root.draft.compactMode
              options: [
                { value: "off", label: "Off" },
                { value: "hover", label: "On hover" },
                { value: "on", label: "On" }
              ]
              foreground: root.tokens.textPrimary
              onChanged: function(value) { root.edit({ compactMode: value }) }
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            id: appsRow
            objectName: "showOpenAppsRow"
            width: parent.width; height: controlFrame.height / root.rowCount
            // Compact On shows only the current number, so it shows no apps.
            readonly property bool usable: root.draft.compactMode !== "on"
            opacity: usable ? 1 : root.tokens.disabledOpacity
            RowLabel {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: appsSwitch.left; anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              text: "Show open apps"
            }
            RowMessage {
              objectName: "showOpenAppsNote"
              text: appsRow.usable ? "App icons next to each workspace" : "Needs compact mode Off or On hover"
            }
            Ui.ToggleSwitch {
              id: appsSwitch
              objectName: "showOpenAppsSwitch"
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              trackHeight: Style.spacing.controlHeight
              checked: root.draft.showOpenApps
              foreground: root.tokens.textPrimary
              interactive: false
            }
            MouseArea {
              anchors.fill: parent
              enabled: appsRow.usable
              cursorShape: Qt.PointingHandCursor
              onClicked: root.edit({ showOpenApps: !root.draft.showOpenApps })
            }
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
  Item {
    width: parent.width; height: Style.space(64)
    Caption {
      objectName: "workspacesNotice"
      x: root.pad; anchors.verticalCenter: parent.verticalCenter
      width: parent.width - actions.width - root.pad * 3
      elide: Text.ElideRight
      text: root.notice
      color: root.notice ? Commons.Color.urgent : root.tokens.textDim
    }
    Row {
      id: actions
      objectName: "workspacesActions"
      visible: root.dirty
      anchors.right: parent.right; anchors.rightMargin: root.pad
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.tokens.space2
      Ui.Button {
        objectName: "workspacesCancel"
        text: "Cancel"; bordered: true
        onClicked: root.reset()
      }
      Ui.Button {
        objectName: "workspacesApply"
        text: root.idle ? "Apply" : "Applying…"
        accent: Commons.Color.accent
        background: Commons.Color.accent
        foreground: Commons.Color.popups.background
        enabled: root.idle
        onClicked: root.apply()
      }
    }
  }
}
