import QtQuick
import "../panel" as PanelUi
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
  property bool narrow: false
  readonly property real pad: tokens.regionPadH
  readonly property var config: service ? service.config : ({})
  readonly property var outputs: service && service.workspaceTarget ? service.workspaceTarget.outputs || [] : []
  readonly property bool idle: !!service && service.state === "idle"
  // The modes differ only across monitors, so one monitor locks the selector.
  readonly property bool singleOutput: outputs.length <= 1
  readonly property int rowCount: 5

  function savedValues() {
    return JSON.parse(JSON.stringify({
      direction: config.direction || "ltr",
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
    return JSON.stringify([values.workspaceMode, values.direction, values.indicatorStyle, values.compactMode, values.showOpenApps,
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
    anchors.left: parent.left; anchors.leftMargin: root.tokens.space2
    anchors.right: parent.right; anchors.rightMargin: root.tokens.space2
    anchors.bottom: parent.bottom; anchors.bottomMargin: root.tokens.space1
    visible: text !== ""
    elide: Text.ElideRight
  }
  component RowLabel: PanelUi.ControlLabel {}
  component RowDropdown: PanelUi.ControlDropdown {
    showLabel: false
    foreground: root.tokens.textPrimary
  }

  PanelUi.FeatureGeometry { id: geometry }

  Item {
    id: workspaceColumns
    width: parent.width
    height: root.narrow ? geometry.stackedHeight : Style.space(428)
    Column {
      id: left
      width: root.narrow ? workspaceColumns.width : workspaceColumns.width * 0.576
      Item {
        width: parent.width; height: geometry.headingHeight
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
        objectName: "workspacesLayout"
        x: root.pad; width: parent.width - root.pad * 2; height: geometry.frameHeight
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
    Item {
      x: root.narrow ? 0 : left.width
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight : 0
      width: root.narrow ? workspaceColumns.width : Math.max(1, Style.normalBorderWidth)
      height: root.narrow ? geometry.separatorSlot : Style.space(428)
      Rectangle {
        objectName: "featureDivider"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.narrow ? geometry.halfGap - height / 2 : 0
        width: root.narrow ? parent.width : Math.max(1, Style.normalBorderWidth)
        height: root.narrow ? Math.max(1, Style.normalBorderWidth) : parent.height
        color: Commons.Color.popups.text; opacity: 0.12
      }
    }
    Column {
      x: root.narrow ? 0 : left.width + Math.max(1, Style.normalBorderWidth)
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight + geometry.separatorSlot : 0
      width: root.narrow ? workspaceColumns.width
        : workspaceColumns.width - left.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Item {
        width: parent.width; height: geometry.headingHeight
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: geometry.headingHeight
          anchors.verticalCenter: parent.verticalCenter
          text: "WORKSPACES"; foreground: Commons.Color.popups.text
        }
      }
      PanelUi.ControlFrame {
        objectName: "featureControlFrame"
        narrow: root.narrow
        id: controlFrame
        height: geometry.frameHeight
        Column {
          anchors.fill: parent
          spacing: 0
          Item {
            width: parent.width; height: controlFrame.height / root.rowCount
            PanelUi.ControlLabel { text: "Mode" }
            RowDropdown {
              objectName: "workspaceModeSelector"
              enabled: !root.singleOutput
              opacity: enabled ? 1 : root.tokens.disabledOpacity
              height: Style.spacing.controlHeight
              value: root.mode
              options: [{ value: "station", label: "Station" }, { value: "repetitive", label: "Repetitive" },
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
              text: "Indicator style"
            }
            RowDropdown {
              id: styleValue
              objectName: "indicatorStyleDropdown"
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
              text: "Compact mode"
            }
            RowMessage {
              objectName: "compactModeNote"
              text: root.draft.compactMode === "off" ? "Every workspace, the current one as a square"
                : root.draft.compactMode === "hover" ? "The current one, the rest on hover"
                : "Only the current one"
            }
            RowDropdown {
              id: compactValue
              objectName: "compactModeDropdown"
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
            width: parent.width; height: controlFrame.height / root.rowCount
            readonly property bool usable: root.mode === "station"
            opacity: usable ? 1 : root.tokens.disabledOpacity
            RowLabel { text: "Stations Direction" }
            RowDropdown {
              objectName: "stationsDirectionDropdown"
              enabled: parent.usable
              value: root.draft.direction
              options: [{ value: "ltr", label: "LTR" }, { value: "rtl", label: "RTL" },
                { value: "ttb", label: "TTB" }, { value: "btt", label: "BTT" }]
              onChanged: function(value) { root.edit({ direction: value }) }
            }
            RowMessage { text: parent.usable ? "" : "only work with Station mode" }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            id: appsRow
            objectName: "showOpenAppsRow"
            width: parent.width; height: controlFrame.height / root.rowCount
            // Compact On shows only the current number, so it shows no apps.
            readonly property bool usable: root.draft.compactMode !== "on"
            opacity: usable ? 1 : root.tokens.disabledOpacity
            RowLabel { text: "Show open apps" }
            RowMessage {
              objectName: "showOpenAppsNote"
              text: appsRow.usable ? "App icons next to each workspace" : "Needs compact mode Off or On hover"
            }
            RowDropdown {
              objectName: "showOpenAppsDropdown"
              enabled: appsRow.usable
              value: root.draft.showOpenApps ? "on" : "off"
              options: [{ value: "off", label: "Off" }, { value: "on", label: "On" }]
              onChanged: function(value) { root.edit({ showOpenApps: value === "on" }) }
            }
          }
        }
      }
    }
  }
  PanelUi.ActionDrawer {
    id: actionDrawer
    objectName: "workspacesDrawer"
    buttonsName: "workspacesActions"
    showButtons: root.dirty
    width: parent.width
    tokens: root.tokens
    narrow: root.narrow
    open: root.dirty
    message: root.notice
    messageColor: root.notice ? Commons.Color.urgent : root.tokens.textDim
    PanelUi.ActionButton {
      widthFactor: 0.6
      objectName: "workspacesCancel"
      text: "Cancel"; bordered: true
      onClicked: root.reset()
    }
    PanelUi.ActionButton {
      widthFactor: 0.6
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
