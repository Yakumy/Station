<!-- summary: For plugin authors: how a widget reaches its own service on a replacement bar. -->
# Widgets that need their own service

This page is for authors of other plugins. Station itself needs none of it.

On Omarchy's bar, `bar.shell.serviceFor(moduleName)` gives a widget its plugin's service.
On a replacement bar, Station's included, it returns null
([contract](contracts/bars.md#plugin-widgets)). The widget shows, but its controls do nothing.

Until Omarchy changes that, a plugin can make its widget work on both bars: its service
publishes a small port through a script that its widget also imports. Station's own panel
uses this pattern ([Bridge paths](architecture.md#bridge-paths)).

## The script

Put a `.pragma library` script in your plugin. Station's
[BarBridge.js](../lib/BarBridge.js) is one you can start from. `publish` takes a function
that reads state and an object of allowed actions. `clear` ignores a service that has
already been replaced.

Import it only from the two top-level entry points, the service's and the widget's.
Quickshell loads a nested type's imports under another URL, which makes a second script
with nothing published in it ([why](architecture.md#bridge-identity)).

## The service

```qml
import QtQuick
import "BarBridge.js" as Bridge

Item {
    id: root
    property bool opened: false
    function toggle() { opened = !opened }

    property var port: null
    Component.onCompleted: port = Bridge.publish(
        function() { return { opened: root.opened } },
        { toggle: function() { root.toggle() } })
    Component.onDestruction: Bridge.clear(port)
}
```

## The widget

The normal lookup comes first, so nothing changes on Omarchy's bar, and the widget
returns to it when a later Omarchy answers on every bar.

```qml
import QtQuick
import "BarBridge.js" as Bridge

Item {
    id: root
    property var bar: null
    property string moduleName: ""
    property bool opened: false

    function ownService() {
        var shell = bar ? bar.shell : null
        return shell && typeof shell.serviceFor === "function"
            ? shell.serviceFor(moduleName) : null
    }

    function refresh() {
        var service = ownService()
        var port = service ? null : Bridge.current()
        var state = service || (port ? port.snapshot() : null)
        opened = !!state && state.opened
    }

    function toggle() {
        var service = ownService()
        var port = service ? null : Bridge.current()
        if (service) service.toggle()
        else if (port) port.call("toggle", [])
        refresh()
    }

    Timer {
        interval: 500
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
```

Look the service and the port up each time. Do not keep either one: a service can start
after its widget, and a plugin reload replaces it under a widget that is still there.

## Rules

- Publish plain values and named actions, never the service object.
- There is one widget per monitor and one service. Open an anchored popout from the widget
  that was clicked, and drop any anchor you registered when that widget is destroyed.
- Check both bars, with more than one monitor, a service that starts after its widget, and
  a service replaced while an old widget is still there.
