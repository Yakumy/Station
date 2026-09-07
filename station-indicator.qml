import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: root

    property var bar
    property string moduleName
    property var settings

    // ---- Station state (~/.local/state/station/state.json) --------------
    FileView {
        id: stateFile
        path: (Quickshell.env("HOME") || "") + "/.local/state/station/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    readonly property var stationState: {
        const raw = stateFile.text()
        if (!raw) return null
        try {
            return JSON.parse(raw)
        } catch (e) {
            return null
        }
    }

    // Initialized, running, and paired (covers: never init'd, stopped, and
    // user-forced single mode — Station itself doesn't distinguish these).
    readonly property bool stationActive:
        stationState !== null
        && stationState.enabled === true
        && stationState.mode === "dual"

    // Live monitor count — independent of state.json, so a physical unplug
    // hides this instantly instead of waiting on Station's own debounce.
    readonly property bool dualMonitorsLive:
        (Hyprland.monitors && Hyprland.monitors.values)
            ? Hyprland.monitors.values.length === 2
            : false

    readonly property bool shouldShow: root.stationActive && root.dualMonitorsLive

    // ---- Current station number -------------------------------------------
    readonly property int currentWorkspace: {
        const workspace = Hyprland.focusedWorkspace
        if (!workspace) return 1
        const id = Number(workspace.id)
        if (id < 1 || id > 10) return 1
        return id
    }

    readonly property int currentStation:
        Math.floor((currentWorkspace + 1) / 2)

    // ---- Theming (matches native widgets — see Ui/WidgetButton.qml) ------
    readonly property color textColor:
        (bar && bar.barForeground) ? bar.barForeground
        : (bar && bar.foreground) ? bar.foreground
        : "white"

    readonly property real labelPixelSize:
        (bar && bar.fontSize) ? bar.fontSize : 12

    visible: root.shouldShow
    implicitWidth: root.shouldShow ? (label.implicitWidth + 16) : 0
    implicitHeight: root.shouldShow ? (bar ? bar.barSize : 26) : 0

    Text {
        id: label
        anchors.centerIn: parent
        text: "[S" + root.currentStation + "]"
        color: root.textColor
        font.family: root.bar ? root.bar.fontFamily : "monospace"
        font.pixelSize: root.labelPixelSize
        font.bold: true
    }
}
