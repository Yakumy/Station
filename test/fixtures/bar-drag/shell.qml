import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// Drives Station's real bar for test/qml/bar-drag.py. The steps run on a timer,
// because layouts, pools and the drag's own animations settle between them.
ShellRoot {
  id: root

  readonly property string resultPath: Quickshell.env("STATION_TEST_RESULT")
  property var failures: []
  property var passed: []
  property int failuresAtStart: 0
  property string current: ""
  property var made: ({})
  property var gone: ({})
  property var fullBar: null
  property var bar: null
  property var surface: null
  property var held: null
  property var kept: ({})
  property string counts: ""
  property int thicker: 0
  property var settles: []
  function recordSettle() { settles = settles.concat([[surface.settle, surface.surfaceThickness, surface.thickness]]) }
  property var steps: []
  property int step: 0
  property int clicks: 0
  property var selected: null

  function check(condition, message) {
    if (!condition) failures = failures.concat([current + ": " + String(message)])
  }
  function same(actual, expected, message) {
    check(JSON.stringify(actual) === JSON.stringify(expected), message + ": " + JSON.stringify(actual) + " is not " + JSON.stringify(expected))
  }
  function bump(map, name) {
    var next = Object.assign({}, root[map])
    next[name] = (next[name] || 0) + 1
    root[map] = next
  }
  function countsNow() { return JSON.stringify(made) + JSON.stringify(gone) }
  function ids(region) {
    return (host.config.bar.layout[region] || []).map(function(entry) { return typeof entry === "string" ? entry : entry.id })
  }
  // What the bar draws in a section, left to right or top to bottom.
  // The indicator has its own scenarios, and stands beside the logo in the others.
  function drawn(region, withIndicator) {
    var slots = bar.moduleSlots.filter(function(slot) { return slot && slot.region === region && slot.moduleName })
    slots.sort(function(a, b) { return root.along(a) - root.along(b) })
    return slots.map(function(slot) { return slot.moduleName }).filter(function(name) { return withIndicator || name !== "yakumy.station.indicator" })
  }
  function slotsOf(name) {
    var found = bar.moduleSlots.filter(function(slot) { return slot && slot.moduleName === name })
    found.sort(function(a, b) { return root.along(a) - root.along(b) })
    return found
  }
  function slotOf(name, region) {
    return slotsOf(name).filter(function(slot) { return !region || slot.region === region })[0] || null
  }
  function along(item) {
    var point = item.mapToItem(null, 0, 0)
    return bar.vertical ? point.y : point.x
  }
  function instanceOf(name) {
    var slot = slotOf(name)
    return slot ? slot.activeItem : null
  }
  function press(slot) {
    held = slot
    tc.mousePress(slot, slot.width / 2, slot.height / 2)
  }
  function pull(slot) {
    var by = 24
    tc.mouseMove(slot, slot.width / 2 + (bar.vertical ? 0 : by), slot.height / 2 + (bar.vertical ? by : 0), -1, Qt.LeftButton)
  }
  function lift(slot) { press(slot); pull(slot) }
  function pointOn(over, fraction) {
    return held.mapFromItem(over, over.width * (bar.vertical ? 0.5 : fraction), over.height * (bar.vertical ? fraction : 0.5))
  }
  function pointAt(over, fraction) {
    var point = pointOn(over, fraction)
    tc.mouseMove(held, point.x, point.y, -1, Qt.LeftButton)
  }
  function letGo(over, fraction) {
    var point = pointOn(over, fraction)
    tc.mouseRelease(held, point.x, point.y)
  }
  // Steps of one drag from a widget onto a place along another.
  function drag(name, region, over, overRegion, fraction) {
    return [
      [function() {
        var slot = root.slotOf(name, region)
        root.check(!!slot, name + " is on the bar")
        if (slot) root.lift(slot)
      }, 160],
      [function() { if (root.slotOf(over, overRegion)) root.pointAt(root.slotOf(over, overRegion), fraction) }, 180],
      [function() { if (root.slotOf(over, overRegion)) root.letGo(root.slotOf(over, overRegion), fraction) }, 420]
    ]
  }
  function scenario(name, rows) {
    return [[function() { root.current = name; root.failuresAtStart = root.failures.length }, 10]].concat(rows, [[function() {
      if (root.failures.length === root.failuresAtStart) root.passed = root.passed.concat([name])
    }, 10]])
  }
  // Every drawn widget stands in the strip, in order and clear of its neighbours,
  // and the center box is centered.
  function geometry(position) {
    var rects = bar.moduleSlots.filter(function(slot) { return slot && slot.region !== "tray" && slot.visible && slot.width > 0 && slot.height > 0 }).map(function(slot) {
      var p = slot.mapToItem(null, 0, 0)
      return { name: slot.moduleName, x: p.x, y: p.y, w: slot.width, h: slot.height }
    })
    var v = bar.vertical
    rects.sort(function(a, b) { return v ? a.y - b.y : a.x - b.x })
    for (var i = 1; i < rects.length; i++) {
      var end = v ? rects[i - 1].y + rects[i - 1].h : rects[i - 1].x + rects[i - 1].w
      check(end <= (v ? rects[i].y : rects[i].x) + 0.5, rects[i - 1].name + " overlaps " + rects[i].name)
    }
    rects.forEach(function(r) {
      var low = { top: r.y, left: r.x, bottom: surface.height - r.y - r.h, right: surface.width - r.x - r.w }[position]
      var high = low + (v ? r.w : r.h)
      check(low >= bar.edgeInset - 0.5 && high <= bar.panelThickness + 0.5, r.name + " is outside the strip: " + low + " to " + high)
    })
    var clock = slotOf("omarchy.clock")
    var middle = clock.mapToItem(null, clock.width / 2, clock.height / 2)
    check(Math.abs((v ? middle.y : middle.x) - (v ? surface.height : surface.width) / 2) <= 1, "the center box is centered: " + (v ? middle.y : middle.x))
  }
  function configure(change, wait) {
    return [function() { host.mutateShellConfig(function(config) { change(config.bar) }) }, wait || 300]
  }
  function layout(bar, next) {
    bar.layout = Object.assign({ left: [], centerBegin: [], center: [], centerEnd: [], right: [], tray: [] }, next)
    delete bar.centerAnchor
    delete bar.stationWidget
    delete bar.stationIndicator
  }

  // Moves the compositor's own pointer, so what it finds under it is decided by the
  // bar's input region, not by Qt. Integers only reach the command.
  function pointer(x, y) {
    mover.command = ["hyprctl", "dispatch", "hl.dsp.cursor.move({ x = " + Math.round(x) + ", y = " + Math.round(y) + " })"]
    mover.running = true
  }
  Process { id: mover }
  // Only the scenarios' own constant dispatchers reach the command.
  function dispatch(call) {
    dispatcher.command = ["hyprctl", "dispatch", call]
    dispatcher.running = true
  }
  Process { id: dispatcher }
  Process { id: flag }
  FloatingWindow { id: app; visible: false; implicitWidth: 400; implicitHeight: 300; title: "app" }
  FloatingWindow { id: overlay; visible: false; implicitWidth: 400; implicitHeight: 300; title: "overlay" }
  function reach(reached, message) {
    function slot() { return root.bar.moduleSlots.filter(function(s) { return s && s.moduleName === "test.a" })[0] }
    return [
      [function() { root.pointer(root.bar.targetScreen.x + root.bar.targetScreen.width / 2, root.bar.targetScreen.y + root.bar.targetScreen.height / 2) }, 200],
      [function() { root.pointerOn(slot(), root.bar) }, 250],
      [function() { root.same(slot().hovered, reached, message) }, 10]
    ]
  }
  // A point in a slot, on the screen. The surface is only the strip, so on the
  // bottom or right edge it does not start at the screen's corner.
  function screenPointIn(slot, instance, x, y) {
    var p = instance.windowScreenPoint(slot.mapToItem(null, x, y), instance.slotWindow(slot))
    return { x: instance.targetScreen.x + p.x, y: instance.targetScreen.y + p.y }
  }
  function pointerOn(slot, instance) {
    var p = screenPointIn(slot, instance, slot.width / 2, slot.height / 2)
    pointer(p.x, p.y)
  }
  function hoverScenario(position, style, wait) {
    var rows = [configure(function(bar) {
      var monitors = bar.monitors || {}
      root.fullBar.instances.forEach(function(one) {
        monitors[one.targetScreenName] = { enabled: true, position: position, style: style, height: 40, contentSize: 0, width: 100, background: "solid" }
      })
      bar.monitors = monitors
    }, 450)]
    for (var n = 0; n < 2; n++) (function(n) {
      rows.push([function() { var one = root.fullBar.instances[n]; root.pointer(one.targetScreen.x + one.targetScreen.width / 2, one.targetScreen.y + one.targetScreen.height / 2) }, 130])
      rows.push([function() {
        var one = root.fullBar.instances[n]
        var slot = one.moduleSlots.filter(function(s) { return s && s.moduleName === "test.reel" })[0]
        root.check(!slot.hovered, "nothing is hovered from the middle of the screen")
        root.pointerOn(slot, one)
      }, 130])
      rows.push([function() {
        var one = root.fullBar.instances[n]
        var slot = one.moduleSlots.filter(function(s) { return s && s.moduleName === "test.reel" })[0]
        root.check(slot.hovered, "the pointer reaches a widget on " + one.targetScreenName + " at the " + position + " (" + style + ")")
      }, 10])
    })(n)
    return rows
  }

  // Omarchy's indicators hide until the pointer is where they would show: just before
  // the center widget here, as Omarchy's default layout has them.
  function revealScenario(position, style) {
    var rows = [configure(function(bar) {
      root.layout(bar, { left: [{ id: "omarchy.menu" }], centerBegin: [{ id: "omarchy.indicators" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] })
      var monitors = {}
      root.fullBar.instances.forEach(function(one) {
        monitors[one.targetScreenName] = { enabled: true, position: position, style: style, height: 40, contentSize: 0, width: 100, background: "solid" }
      })
      bar.monitors = monitors
    }, 500)]
    function found(one, name) { return one.moduleSlots.filter(function(s) { return s && s.moduleName === name })[0] }
    function length(slot) { return root.bar.vertical ? slot.height : slot.width }
    for (var n = 0; n < 2; n++) (function(n) {
      rows.push([function() { var one = root.fullBar.instances[n]; root.pointer(one.targetScreen.x + one.targetScreen.width / 2, one.targetScreen.y + one.targetScreen.height / 2) }, 400])
      rows.push([function() {
        var one = root.fullBar.instances[n]
        root.same(length(found(one, "omarchy.indicators")), 0, "hidden from the middle of the screen")
        var clock = found(one, "omarchy.clock")
        var p = root.screenPointIn(clock, one, clock.width / 2, clock.height / 2)
        root.pointer(p.x - (root.bar.vertical ? 0 : clock.width / 2 + 20), p.y - (root.bar.vertical ? clock.height / 2 + 20 : 0))
      }, 400])
      rows.push([function() {
        var one = root.fullBar.instances[n]
        root.check(length(found(one, "omarchy.indicators")) > 40, "shown on " + one.targetScreenName + " at the " + position + " (" + style + "): " + length(found(one, "omarchy.indicators")))
      }, 10])
    })(n)
    return rows
  }

  component Widget: Rectangle {
    property var bar: null
    property string moduleName: ""
    property var settings: ({})
    property string fixedEdge: "center"
    property bool tooltipHovered: false
    property int heldButtons: Qt.NoButton
    implicitWidth: 30
    implicitHeight: 20
    color: "steelblue"
    function triggerPress(button) { root.clicks++ }
    onModuleNameChanged: if (moduleName) root.bump("made", moduleName)
    Component.onDestruction: root.bump("gone", moduleName)
  }
  Component { id: testWidget; Widget {} }
  // A widget with a panel, as a plugin's Panel.qml is one.
  Component {
    id: testPanel
    Widget {
      property bool opened: false
      function open() { opened = true; if (bar) bar.requestPopout(this) }
      function close() { opened = false; if (bar) bar.releasePopout(this) }
      color: "seagreen"
    }
  }
  // Station's logo widget, with the port the bar's indicator reads.
  Component {
    id: testStation
    Widget {
      id: logo
      property bool opened: false
      function open() { opened = true; if (bar) bar.requestPopout(this) }
      function close() { opened = false; if (bar) bar.releasePopout(this) }
      color: "olive"
      readonly property QtObject indicator: QtObject {
        property int stationNumber: 2
        property string compactMode: "off"
        property bool showOpenApps: false
        property var stationApps: ({ 1: [], 2: [], 3: [] })
        property var workspaceMap: null
        property var workspaceApps: ({})
        property string indicatorStyle: "prefixed"
        function select(number, screenName) { root.selected = [number, screenName] }
      }
    }
  }
  Component {
    id: testTray
    Item {
      id: tray
      property var bar: null
      property string moduleName: ""
      property var settings: ({})
      property string fixedEdge: "center"
      property Item sectionHost: section
      readonly property string sectionEdge: fixedEdge === "start" ? "start" : "end"
      readonly property var sectionShown: ({ x: section.x, y: section.y, width: section.implicitWidth, height: section.implicitHeight })
      // Pinned icons, the section, then the chevron, along the bar. As on Omarchy's
      // bar, a drop near the tray's ends lands beside the tray, not in it.
      readonly property bool upright: !!bar && bar.vertical
      implicitWidth: upright ? 20 : 60 + section.implicitWidth
      implicitHeight: upright ? 60 + section.implicitHeight : 20
      Item {
        id: section
        x: tray.upright ? 0 : 30
        y: tray.upright ? 30 : 0
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        width: implicitWidth
        height: implicitHeight
      }
    }
  }

  QtObject {
    id: registry
    property int revision: 0
    property var widgets: ({
      "omarchy.menu": { component: testWidget },
      "omarchy.clock": { component: testWidget },
      "yakumy.station": { component: testStation },
      "test.reel": { component: testPanel },
      "omarchy.indicators": { component: indicators },
      "test.a": { component: testWidget },
      "test.b": { component: testWidget },
      "test.c": { component: testWidget },
      "test.twin": { component: testWidget },
      "test.inner": { component: testWidget },
      "test.tray": { component: testTray }
    })
    readonly property Component indicators: Qt.createComponent("plugins/bar/widgets/Indicators.qml")
    function metadataFor(id) { return widgets[id] ? { firstParty: true } : null }
  }

  QtObject {
    id: host
    property int writes: 0
    property var config: ({ bar: {
      id: "yakumy.station", position: "top", background: "opaque",
      layout: {
        left: [{ id: "omarchy.menu" }, { id: "test.reel" }],
        center: [{ id: "omarchy.clock" }],
        right: [{ id: "test.twin" }, { id: "test.b" }, { id: "test.twin" }, { id: "test.c" }]
      }
    } })
    function firstPartyServiceFor(id) { return null }
    function mutateShellConfig(mutator) {
      var copy = JSON.parse(JSON.stringify(config))
      mutator(copy)
      writes++
      config = copy
      return true
    }
  }

  TestCase { id: tc; name: "bar-drag"; when: false }
  FileView { id: result; path: root.resultPath }

  Component.onCompleted: {
    var all = [[function() {
      root.current = "loads"
      var component = Qt.createComponent("file://" + Quickshell.env("STATION_BAR_ENTRY"))
      if (component.status !== Component.Ready) return root.check(false, component.errorString())
      root.fullBar = component.createObject(root, { barWidgetRegistry: registry, shell: host, barConfig: host.config.bar })
      root.fullBar.barConfig = Qt.binding(function() { return host.config.bar })
    }, 1600], [function() {
      root.check(root.fullBar && root.fullBar.instances.length === 2, "one bar per output")
      root.bar = root.fullBar.instances[0]
      root.surface = root.bar.slotWindow(root.slotOf("test.b"))
      root.check(!!root.surface, "the bar is drawn")
    }, 10]]

    all = all.concat(
      scenario("two entries alike keep their own instances through a drag", [
        [function() {
          var twins = root.slotsOf("test.twin")
          root.check(twins.length === 2, "both twins are drawn")
          root.kept = { first: twins[0].activeItem, second: twins[1].activeItem }
          root.counts = root.countsNow()
          root.lift(twins[0])
        }, 180],
        [function() { root.pointAt(root.slotOf("test.reel"), 0.8) }, 180],
        [function() { root.letGo(root.slotOf("test.reel"), 0.8) }, 420],
        [function() {
          root.same(root.ids("left"), ["omarchy.menu", "test.reel", "test.twin"], "left")
          root.same(root.ids("right"), ["test.b", "test.twin", "test.c"], "right")
          root.check(root.slotOf("test.twin", "left").activeItem === root.kept.first, "the dragged twin arrives as itself")
          root.check(root.slotOf("test.twin", "right").activeItem === root.kept.second, "the other twin stays")
          root.check(root.countsNow() === root.counts, "nothing is rebuilt: " + root.countsNow())
        }, 10]
      ]),

      scenario("a widget moves to either side of Station's own icon", [
        configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }, { id: "test.b" }] }) }),
        [function() { root.same(root.drawn("left"), ["omarchy.menu", "yakumy.station", "test.reel"], "Station starts beside the menu") }, 10]
      ].concat(drag("test.reel", "left", "yakumy.station", "left", 0.2), [
        [function() {
          root.same(root.drawn("left"), ["omarchy.menu", "test.reel", "yakumy.station"], "before Station")
          root.same(root.ids("left"), ["omarchy.menu", "test.reel"], "Station is not saved in the layout")
        }, 10]
      ], drag("test.reel", "left", "yakumy.station", "left", 0.8), [
        [function() { root.same(root.drawn("left"), ["omarchy.menu", "yakumy.station", "test.reel"], "after Station") }, 10]
      ])),

      scenario("Station's own icon drags to any section and keeps its instance", [
        configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }, { id: "test.b" }] }) }),
        [function() { root.kept = { station: root.instanceOf("yakumy.station") }; root.counts = root.countsNow() }, 10]
      ].concat(drag("yakumy.station", "left", "test.a", "right", 0.8), [
        [function() {
          root.same(root.drawn("right"), ["test.a", "yakumy.station", "test.b"], "right")
          root.same(root.ids("right"), ["test.a", "test.b"], "saved right")
          root.same(root.ids("left"), ["omarchy.menu", "test.reel"], "saved left")
          root.same(host.config.bar.stationWidget, { section: "right", index: 1 }, "its place is saved")
          root.check(root.instanceOf("yakumy.station") === root.kept.station, "it arrives as itself")
          root.check(root.countsNow() === root.counts, "nothing is rebuilt: " + root.countsNow())
          var other = root.fullBar.instances[1]
          root.check(other.moduleSlots.some(function(slot) { return slot.moduleName === "yakumy.station" && slot.region === "right" }), "the other monitor's bar follows")
        }, 10]
      ], drag("test.a", "right", "test.b", "right", 0.8), [
        [function() { root.same(root.drawn("right"), ["yakumy.station", "test.b", "test.a"], "a widget moves past it") }, 10]
      ], drag("yakumy.station", "right", "omarchy.menu", "left", 0.2), [
        [function() { root.same(root.drawn("left"), ["yakumy.station", "omarchy.menu", "test.reel"], "before the menu") }, 10]
      ])),

      scenario("the indicator is its own widget, beside the logo until either is moved", [
        configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }, { id: "test.b" }] }) }),
        [function() {
          root.same(root.drawn("left", true), ["omarchy.menu", "yakumy.station", "yakumy.station.indicator", "test.reel"], "together")
          root.kept = { logo: root.instanceOf("yakumy.station"), indicator: root.instanceOf("yakumy.station.indicator") }
          root.check(root.kept.indicator.width > 0 && root.kept.indicator.stationNumber === 2, "fed by the logo")
        }, 10]
      ].concat(drag("yakumy.station.indicator", "left", "test.a", "right", 0.8), [
        [function() {
          root.same([root.drawn("left", true), root.drawn("right", true)], [["omarchy.menu", "yakumy.station", "test.reel"], ["test.a", "yakumy.station.indicator", "test.b"]], "the indicator alone")
          root.same([host.config.bar.stationIndicator, host.config.bar.stationWidget], [{ section: "right", index: 1 }, undefined], "saved")
          root.check(root.instanceOf("yakumy.station.indicator") === root.kept.indicator, "it arrives as itself")
        }, 10]
      ], drag("yakumy.station", "left", "test.reel", "left", 0.8), [
        [function() {
          root.same([root.drawn("left", true), root.drawn("right", true)], [["omarchy.menu", "test.reel", "yakumy.station"], ["test.a", "yakumy.station.indicator", "test.b"]], "the logo alone")
          root.check(root.instanceOf("yakumy.station") === root.kept.logo && root.instanceOf("yakumy.station.indicator") === root.kept.indicator, "both as themselves")
          var label = tc.findChild(root.kept.indicator, "stationLabel-3")
          var at = label.mapToItem(root.slotOf("yakumy.station.indicator"), label.width / 2, label.height / 2)
          tc.mouseClick(root.slotOf("yakumy.station.indicator"), at.x, at.y)
        }, 150],
        [function() { root.same(root.selected, [3, root.bar.targetScreenName], "its numbers still work"); root.lift(root.slotOf("yakumy.station.indicator")) }, 160],
        [function() { tc.mouseMove(root.held, 10, 400, -1, Qt.LeftButton) }, 220],
        [function() { root.check(root.bar.barDragRemoveArmed === false, "not removable"); tc.mouseRelease(root.held, 10, 400) }, 700]
      ], drag("yakumy.station.indicator", "right", "yakumy.station", "left", 0.8), [
        [function() {
          root.same(root.drawn("left", true), ["omarchy.menu", "test.reel", "yakumy.station", "yakumy.station.indicator"], "together again")
          root.check(host.config.bar.stationIndicator === undefined, "and following the logo")
        }, 10]
      ])),

      scenario("a held widget drags itself, not the bar", [
        configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] }) }),
        [function() { root.press(root.slotOf("test.reel")) }, 500],
        [function() { root.check(root.bar.barMoveActive !== true, "holding a widget does not move the bar"); root.pull(root.held) }, 180],
        [function() { root.pointAt(root.slotOf("test.a"), 0.8) }, 180],
        [function() { root.letGo(root.slotOf("test.a"), 0.8) }, 420],
        [function() { root.same(root.ids("right"), ["test.a", "test.reel"], "right"); root.same(root.bar.position, "top", "position") }, 10]
      ]),

      scenario("a click is a click, and a drag is not", [
        [function() { root.clicks = 0; tc.mouseClick(root.slotOf("test.a"), 10, 10) }, 120],
        [function() { root.same(root.clicks, 1, "clicks") }, 10]
      ].concat(drag("test.a", "right", "test.reel", "right", 0.8), [
        [function() { root.same(root.clicks, 1, "clicks after a drag") }, 10]
      ])),

      scenario("pulling a widget off the bar removes it, and Station's never", [
        [function() { root.lift(root.slotOf("test.reel")) }, 160],
        [function() { tc.mouseMove(root.held, 10, 400, -1, Qt.LeftButton) }, 220],
        [function() { root.check(root.bar.barDragRemoveArmed === true, "armed"); tc.mouseRelease(root.held, 10, 400) }, 1200],
        [function() { root.same(root.ids("right"), ["test.a"], "right") }, 10],
        [function() { root.lift(root.slotOf("yakumy.station")) }, 160],
        [function() { tc.mouseMove(root.held, 10, 400, -1, Qt.LeftButton) }, 220],
        [function() { root.check(root.bar.barDragRemoveArmed === false, "Station's icon is not armed"); tc.mouseRelease(root.held, 10, 400) }, 700],
        [function() { root.check(!!root.slotOf("yakumy.station"), "Station's icon goes back") }, 10]
      ]),

      scenario("a drag that leaves the strip keeps the pointer until release", [
        configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] }) }),
        [function() {
          root.check(root.surface.implicitHeight === root.surface.thickness, "the surface is only as tall as its strip: " + root.surface.implicitHeight + " against " + root.surface.thickness)
          root.lift(root.slotOf("test.reel"))
        }, 160],
        [function() { tc.mouseMove(root.held, 60, 40, -1, Qt.LeftButton) }, 120],
        [function() {
          root.check(root.bar.barDragSource !== null, "still dragging off the strip")
          root.check(root.surface.implicitHeight === root.surface.thickness, "a drag leaves the surface the size of its strip: " + root.surface.implicitHeight)
          root.pointAt(root.slotOf("test.a"), 0.2)
        }, 180],
        [function() { root.letGo(root.slotOf("test.a"), 0.2) }, 420],
        [function() { root.same(root.ids("right"), ["test.reel", "test.a"], "right") }, 10]
      ]),

      scenario("an older centerAnchor keeps its widget in the middle through a drop", [
        configure(function(bar) {
          root.layout(bar, { left: [{ id: "omarchy.menu" }], center: [{ id: "test.a" }, { id: "test.b" }, { id: "omarchy.clock" }, { id: "test.c" }], right: [{ id: "test.reel" }] })
          delete bar.layout.centerBegin
          delete bar.layout.centerEnd
          bar.centerAnchor = "omarchy.clock"
        }),
        [function() {
          root.same(root.drawn("centerBegin"), ["test.a", "test.b"], "before the clock")
          root.same(root.drawn("centerEnd"), ["test.c"], "after the clock")
          root.kept = { clock: root.along(root.slotOf("omarchy.clock")) }
          root.check(Math.abs(root.kept.clock + 15 - root.surface.width / 2) <= 1, "the clock is in the middle: " + root.kept.clock)
        }, 10]
      ].concat(drag("test.reel", "right", "test.c", "centerEnd", 0.8), [
        [function() {
          root.same(root.ids("center"), ["omarchy.clock"], "center")
          root.same(root.ids("centerBegin"), ["test.a", "test.b"], "centerBegin")
          root.same(root.ids("centerEnd"), ["test.c", "test.reel"], "centerEnd")
          root.check(host.config.bar.centerAnchor === undefined, "the anchor is gone once the sections hold it")
          root.check(Math.abs(root.along(root.slotOf("omarchy.clock")) - root.kept.clock) <= 1, "the clock has not moved")
        }, 10]
      ])),

      scenario("widgets go in and out of the tray's drawer", [
        configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }, { id: "test.tray" }], tray: [{ id: "test.inner" }] }) }),
        [function() {
          root.same(root.drawn("tray"), ["test.inner"], "drawer")
          root.same(root.slotOf("test.inner").activeItem.fixedEdge, "end", "the edge a right-hand tray gives")
        }, 10]
      ].concat(drag("test.reel", "left", "test.inner", "tray", 0.8), [
        [function() { root.same(root.ids("tray"), ["test.inner", "test.reel"], "dropped in") }, 10]
      ], drag("test.inner", "tray", "omarchy.menu", "left", 0.8), [
        [function() { root.same(root.ids("tray"), ["test.reel"], "dragged out"); root.same(root.ids("left"), ["omarchy.menu", "test.inner"], "left") }, 10]
      ]))
    )

    // The same drags on each edge, Pill and default, zoomed and not.
    var edges = [["top", "default", 0], ["top", "pill", 18], ["bottom", "default", 18], ["bottom", "pill", 0],
                 ["left", "default", 18], ["left", "pill", 0], ["right", "default", 0], ["right", "pill", 18]]
    edges.forEach(function(row) {
      all = all.concat(scenario("drags work on a " + row[0] + " " + row[1] + " bar, content " + (row[2] || "default"), [
        configure(function(bar) {
          root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }, { id: "test.tray" }], tray: [{ id: "test.inner" }] })
          var monitors = {}
          root.fullBar.instances.forEach(function(one) {
            monitors[one.targetScreenName] = { enabled: true, position: row[0], style: row[1], height: 40, contentSize: row[2], width: 100, background: "solid" }
          })
          bar.monitors = monitors
        }, 600),
        [function() {
          root.same(root.bar.position, row[0], "position")
          root.kept = { reel: root.instanceOf("test.reel"), station: root.instanceOf("yakumy.station") }
          root.check(!row[2] || root.bar.contentScale > 1, "zoomed: " + root.bar.contentScale)
          var slot = root.slotOf("test.reel")
          var strip = slot.mapToItem(null, slot.width / 2, slot.height / 2)
          var depth = { top: strip.y, bottom: root.surface.height - strip.y, left: strip.x, right: root.surface.width - strip.x }[row[0]]
          root.check(depth > 0 && depth < root.bar.panelThickness, "drawn in the strip on that edge: " + depth)
          root.geometry(row[0])
        }, 10]
      ].concat(drag("test.reel", "left", "test.a", "right", 0.8), drag("yakumy.station", "left", "test.reel", "right", 0.2), [
        [function() {
          root.same(root.drawn("right"), ["test.a", "yakumy.station", "test.reel", "test.tray"], "right")
          root.check(root.instanceOf("test.reel") === root.kept.reel && root.instanceOf("yakumy.station") === root.kept.station, "the very instances dragged")
        }, 10]
      ], drag("test.a", "right", "test.inner", "tray", 0.8), [
        [function() { root.same(root.ids("tray"), ["test.inner", "test.a"], "into the drawer"); root.geometry(row[0]) }, 10],
        configure(function(bar) { bar.layout.tray = [] }, 250)
      ], drag("test.reel", "right", "test.tray", "right", 0.5), [
        [function() { root.same(root.ids("tray"), ["test.reel"], "into an empty drawer") }, 10],
        configure(function(bar) { bar.layout.tray = [{ id: "test.inner" }]; bar.layout.right.push({ id: "test.reel" }) }, 250)
      ])))
    })

    // Every ordered pair of edges: an input region left behind on the old edge shows
    // only after particular moves.
    var tour = ["top", "right", "left", "bottom", "top", "left", "right", "bottom", "right", "top", "bottom", "left", "top"]
    ;["default", "pill"].forEach(function(style) {
      var rows = [configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }, { id: "test.reel" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] }) }, 250)]
      tour.forEach(function(edge) { rows = rows.concat(root.hoverScenario(edge, style)) })
      all = all.concat(scenario("the pointer reaches the bar after every move between edges, " + style, rows))
    })

    // Solid and Blur keep the Pill's space from the monitor's edge and ends. Nothing of a
    // Transparent default bar is drawn, so it starts at the edge.
    ;["solid", "blur", "transparent"].forEach(function(background) {
      ;[100, 97].forEach(function(width) {
        var rows = []
        ;["top", "right", "bottom", "left"].forEach(function(edge) {
          rows.push(configure(function(bar) {
            root.layout(bar, { left: [{ id: "omarchy.menu" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] })
            bar.monitors = {}
            root.fullBar.instances.forEach(function(one) {
              bar.monitors[one.targetScreenName] = { enabled: true, position: edge, style: "default", height: 40, contentSize: 0, width: width, background: background }
            })
          }, 400), [function() {
            root.fullBar.instances.forEach(function(one) {
              var item = one.slotWindow(one.moduleSlots.filter(function(s) { return s && s.moduleName === "omarchy.clock" })[0]).contentItem
              var content = tc.findChild(item, "barContent")
              var at = content.mapToItem(null, 0, 0)
              var gaps = { top: at.y, left: at.x, bottom: item.height - at.y - content.height, right: item.width - at.x - content.width }
              var gap = background === "transparent" ? 0 : 8
              var length = one.vertical ? item.height : item.width
              var end = Math.max(gap, (length - Math.round(length * width / 100)) / 2)
              root.same(gaps[edge], gap, edge + " edge")
              root.same(one.panelThickness - one.barSize, gap, "reserved beside the bar")
              ;(one.vertical ? ["top", "bottom"] : ["left", "right"]).forEach(function(side) {
                root.check(Math.abs(gaps[side] - end) <= 0.5, side + " end of a " + edge + " bar: " + gaps[side] + " is not " + end)
              })
            })
            root.bar = root.fullBar.instances[0]
            root.geometry(edge)
          }, 10])
        })
        all = all.concat(scenario("a " + background + " default bar's space from its monitor, width " + width, rows))
      })
    })

    ;["default", "pill"].forEach(function(style) {
      var rows = []
      ;["top", "right", "bottom", "left"].forEach(function(edge) { rows = rows.concat(root.revealScenario(edge, style)) })
      all = all.concat(scenario("Omarchy's indicators show under the pointer on every edge, " + style, rows))
    })

    // Drag the free bar from every edge to every edge, released at three places along
    // it, on both bars: the edge asked for is the one under the pointer.
    var pairs = []
    var edgeNames = ["top", "right", "bottom", "left"]
    edgeNames.forEach(function(from) { edgeNames.forEach(function(to) { if (from !== to) pairs.push([from, to]) }) })
    ;["default", "pill"].forEach(function(style) {
      var rows = [configure(function(bar) { root.layout(bar, { left: [{ id: "omarchy.menu" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] }) }, 250)]
      pairs.forEach(function(pair) {
        rows.push(configure(function(bar) { root.fullBar.instances.forEach(function(one) {
          bar.monitors[one.targetScreenName] = { enabled: true, position: pair[0], style: style, height: 40, contentSize: 0, width: 100, background: "solid" } }) }, 260))
        ;[0.25, 0.5, 0.75].forEach(function(where) {
          rows.push([function() {
            root.fullBar.instances.forEach(function(one) {
              var content = one.slotWindow(one.moduleSlots.filter(function(s) { return s && s.moduleName === "omarchy.clock" })[0]).contentItem
              var w = content.width, h = content.height, depth = one.panelThickness - one.barSize / 2 - (one.contentOffset === 0 ? one.edgeInset : 0)
              // The surface is only the strip, so the release point is the screen's,
              // moved into the surface's own coordinates.
              var sw = one.targetScreen.width, sh = one.targetScreen.height
              var ox = pair[0] === "right" ? sw - w : 0, oy = pair[0] === "bottom" ? sh - h : 0
              var start = { top: [w * 0.35, depth], bottom: [w * 0.35, h - depth], left: [depth, h * 0.35], right: [w - depth, h * 0.35] }[pair[0]]
              var end = { top: [sw * where, 30], bottom: [sw * where, sh - 30], left: [30, sh * where], right: [sw - 30, sh * where] }[pair[1]]
              end = [end[0] - ox, end[1] - oy]
              var asked = ""
              function note(position) { asked = position }
              one.positionRequested.connect(note)
              tc.mousePress(content, start[0], start[1])
              tc.mouseMove(content, start[0] + 12, start[1] + 12, -1, Qt.LeftButton)
              tc.mouseMove(content, (start[0] + end[0]) / 2, (start[1] + end[1]) / 2, -1, Qt.LeftButton)
              tc.mouseMove(content, end[0], end[1], -1, Qt.LeftButton)
              var shown = one.barMoveCandidate
              tc.mouseRelease(content, end[0], end[1])
              one.positionRequested.disconnect(note)
              root.same([shown, asked], [pair[1], pair[1]], one.targetScreenName + " " + pair.join(" to ") + " at " + where)
              root.check(!one.barMoveActive, "the move ends")
            })
          }, 30])
        })
      })
      all = all.concat(scenario("the bar is asked to go to the edge it is released at, " + style, rows))
    })

    // Omarchy #19897: only a fullscreen window that covers the screen takes the bar's input.
    all = all.concat(scenario("the bar takes clicks unless a fullscreen window covers it", [
      configure(function(bar) {
        root.layout(bar, { left: [{ id: "omarchy.menu" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] })
        root.fullBar.instances.forEach(function(one) {
          bar.monitors[one.targetScreenName] = { enabled: true, position: "top", style: "default", height: 40, contentSize: 0, width: 100, background: "solid" }
        })
      }, 500),
      [function() { root.bar = root.fullBar.instances[0] }, 10]
    ].concat(reach(true, "with no window"), [
      [function() { app.visible = true }, 500],
      [function() { root.dispatch('hl.dsp.window.fullscreen({ mode = "fullscreen" })') }, 600]
    ], reach(false, "under a fullscreen window"), [
      [function() { root.dispatch('hl.dsp.workspace.toggle_special("test")') }, 400],
      [function() { overlay.visible = true }, 600]
    ], reach(true, "under a special workspace over that window"), [
      // Hyprland closes a special workspace when its last window closes.
      [function() { overlay.visible = false }, 600]
    ], reach(false, "when the special workspace closes"), [
      [function() { app.visible = false }, 600]
    ], reach(true, "when the fullscreen window closes"))))

    // Omarchy's shell has one bar for all screens, so a widget's broadcast reaches each.
    function recordingShown() {
      return root.fullBar.instances.map(function(one) {
        var widget = one.moduleSlots.filter(function(s) { return s && s.moduleName === "omarchy.indicators" })[0]
        return !!widget && widget.activeItem.activeIndicatorIds.indexOf("ScreenRecording") !== -1
      })
    }
    function setRecording(on) {
      flag.command = [on ? "touch" : "rm", Quickshell.env("HOME") + "/recording"]
      flag.running = true
    }
    function broadcastFrom(n) {
      root.fullBar.instances[n].moduleSlots.filter(function(s) { return s && s.moduleName === "omarchy.indicators" })[0].activeItem.broadcast("refresh")
    }
    var relay = [configure(function(bar) {
      root.layout(bar, { left: [{ id: "omarchy.menu" }], centerBegin: [{ id: "omarchy.indicators" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] })
    }, 600), [function() { root.same(recordingShown(), [false, false], "not recording") }, 10]]
    ;[0, 1].forEach(function(n) {
      relay = relay.concat([
        [function() { setRecording(true) }, 200],
        [function() { broadcastFrom(n) }, 500],
        [function() { root.same(recordingShown(), [true, true], "a start relayed by monitor " + n) }, 10],
        [function() { setRecording(false) }, 200],
        [function() { broadcastFrom(n) }, 500],
        [function() { root.same(recordingShown(), [false, false], "a stop relayed by monitor " + n) }, 10]
      ])
    })
    all = all.concat(scenario("a widget's refresh reaches its copies on every monitor", relay))

    all = all.concat(scenario("a side change keeps every widget and its open panel", [
      configure(function(bar) {
        root.layout(bar, { left: [{ id: "omarchy.menu" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }, { id: "yakumy.station" }, { id: "test.reel" }, { id: "test.tray" }], tray: [{ id: "test.inner" }] })
        root.fullBar.instances.forEach(function(one) { bar.monitors[one.targetScreenName].position = "right" })
      }, 500),
      [function() {
        root.kept = { reel: root.instanceOf("test.reel"), station: root.instanceOf("yakumy.station") }
        root.counts = root.countsNow()
        root.kept.reel.open()
        root.check(root.bar.activePopout === root.kept.reel, "open")
      }, 100],
      configure(function(bar) { for (var name in bar.monitors) bar.monitors[name].position = "top" }, 500),
      [function() {
        root.check(root.instanceOf("test.reel") === root.kept.reel && root.instanceOf("yakumy.station") === root.kept.station, "the same instances")
        root.check(root.kept.reel.opened && root.bar.activePopout === root.kept.reel, "still open")
        root.check(root.countsNow() === root.counts, "nothing is rebuilt")
        root.kept.reel.close()
      }, 50]
    ]), scenario("one monitor's bar moves without the other", [
      configure(function(bar) { bar.monitors[root.fullBar.instances[1].targetScreenName].position = "left" }, 500),
      [function() {
        root.same([root.fullBar.instances[0].position, root.fullBar.instances[1].position], ["top", "left"], "positions")
        root.same(root.drawn("left"), root.fullBar.instances[1].layoutWidgets.sections.left.map(function(key) { return key.split("#")[0] }), "one layout")
      }, 10]
    ]), scenario("what Omarchy's shell asks of its bar answers for every monitor", [
      [function() {
        ["cycleBackground", "debugBarGeometry", "hideBarWidget", "isBarWidgetOpen", "panelWidgetIdAt", "summonBarWidget", "barSizeFor"].forEach(function(name) {
          root.check(typeof root.fullBar[name] === "function", name)
        })
        root.same(Object.keys(root.fullBar.screenBarSizes).sort(), root.fullBar.instances.map(function(one) { return one.targetScreenName }).sort(), "screenBarSizes")
        root.check(root.fullBar.debugBarGeometry().length >= 2 * 6, "debugBarGeometry")
        root.check(root.fullBar.summonBarWidget("test.reel"), "summon")
        root.check(root.fullBar.isBarWidgetOpen("test.reel"), "open")
        root.check(root.fullBar.hideBarWidget("test.reel") && !root.fullBar.isBarWidgetOpen("test.reel"), "hide")
        root.same(root.fullBar.panelWidgetIdAt("right", 1), "yakumy.station", "the first panel in the right section")
      }, 100]
    ]), scenario("a click target reports its press while held", [
      [function() { root.press(root.slotOf("test.reel")) }, 60],
      [function() { root.same(root.instanceOf("test.reel").heldButtons, Qt.LeftButton, "held"); tc.mouseRelease(root.held, 5, 5) }, 60],
      [function() { root.same(root.instanceOf("test.reel").heldButtons, Qt.NoButton, "released") }, 10]
    ]), scenario("a drag whose widget leaves the layout lets go", [
      [function() { root.lift(root.slotOf("test.reel")) }, 160],
      configure(function(bar) { for (var s in bar.layout) bar.layout[s] = bar.layout[s].filter(function(e) { return e.id !== "test.reel" }) }, 300),
      [function() { root.check(root.bar.barDragSource === null, "no drag"); tc.mouseRelease(root.surface.contentItem, 5, 300) }, 60]
    ]), scenario("the bar's surface is its strip, and settles into a new edge or thickness", [
      configure(function(bar) {
        root.layout(bar, { left: [{ id: "omarchy.menu" }], center: [{ id: "omarchy.clock" }], right: [{ id: "test.a" }] })
        root.fullBar.instances.forEach(function(one) {
          bar.monitors[one.targetScreenName] = { enabled: true, position: "top", style: "default", height: 40, contentSize: 0, width: 100, background: "solid" }
        })
      }, 600),
      [function() {
        root.bar = root.fullBar.instances[0]
        root.surface = root.bar.slotWindow(root.slotOf("test.a"))
        root.check(root.surface.implicitHeight === root.surface.thickness && root.surface.height === root.surface.thickness, "a top bar's surface is only as tall as its strip: " + root.surface.height + " against " + root.surface.thickness)
        // Moving to a side edge resizes the surface, so the strip turns clear
        // before the surface moves.
        host.mutateShellConfig(function(config) { config.bar.monitors[root.bar.targetScreenName].position = "left" })
        root.check(root.surface.resizeDue && root.surface.surfaceEdge === "top", "a strip moving to a side edge clears before its surface moves: " + root.surface.resizeDue + " " + root.surface.surfaceEdge)
      }, 1200],
      [function() {
        root.check(root.surface.settle === "" && root.surface.surfaceEdge === "left", "the surface settles on the left edge: " + root.surface.settle + " " + root.surface.surfaceEdge)
        root.check(root.surface.implicitWidth === root.surface.thickness && root.surface.width === root.surface.thickness, "a side bar's surface is only as wide as its strip: " + root.surface.width + " against " + root.surface.thickness)
        root.check(root.fullBar.instances[1].position === "top", "the other monitor's bar stays")
        // A thinner bar on the same edge resizes the surface too: Transparent
        // keeps no space from the monitor's edge.
        // The height reaches the bar a moment later, so record each settle state.
        root.thicker = root.surface.surfaceThickness
        root.settles = []
        root.surface.settleChanged.connect(root.recordSettle)
        host.mutateShellConfig(function(config) { config.bar.monitors[root.bar.targetScreenName].background = "transparent" })
      }, 1200],
      [function() {
        root.surface.settleChanged.disconnect(root.recordSettle)
        root.check(root.surface.thickness < root.thicker, "the bar thins: " + root.surface.thickness)
        root.check(root.settles.some(function(one) { return one[0] === "clearing" && one[1] === root.thicker && one[2] < root.thicker }), "a thinner strip clears before its surface shrinks: " + JSON.stringify(root.settles))
        root.check(root.surface.settle === "" && root.surface.surfaceThickness === root.surface.thickness && root.surface.width === root.surface.thickness, "the surface settles at the new thickness: " + root.surface.width + " against " + root.surface.thickness)
        root.check(!root.surface.resizeDue, "the strip shows again")
      }, 100]
    ]), scenario("Station's logo shows though the shell leaves it uncompiled", [
      // Omarchy 4.6 registers a widget its saved layout lacks with no component,
      // and Station's logo is never in the saved layout.
      [function() {
        root.check(!!root.instanceOf("yakumy.station") && !("bridgeCurrent" in root.instanceOf("yakumy.station")), "drawn from the shell's component")
        var next = Object.assign({}, registry.widgets)
        next["yakumy.station"] = { component: null }
        registry.widgets = next
        registry.revision++
      }, 3000],
      [function() {
        root.check(!!root.fullBar.stationWidgetComponent, "the bar compiles Panel.qml itself")
        root.fullBar.instances.forEach(function(one) {
          var slot = one.moduleSlots.filter(function(s) { return s && s.moduleName === "yakumy.station" })[0]
          root.check(!!slot && !!slot.activeItem && ("bridgeCurrent" in slot.activeItem), one.targetScreenName + " draws Station's own logo")
        })
        var next = Object.assign({}, registry.widgets)
        next["yakumy.station"] = { component: testStation }
        registry.widgets = next
        registry.revision++
      }, 300],
      [function() { root.check(!!root.instanceOf("yakumy.station") && !("bridgeCurrent" in root.instanceOf("yakumy.station")), "the shell's component wins once it has one") }, 10]
    ]))

    steps = all
    stepper.start()
  }

  Timer {
    id: stepper
    interval: 10
    onTriggered: {
      if (root.step >= root.steps.length) {
        result.setText(JSON.stringify({ passed: root.passed, failures: root.failures, thickness: root.fullBar.screenBarSizes,
          positions: root.fullBar.instances.map(function(one) { return [one.targetScreenName, one.position] }) }))
        return
      }
      var now = root.steps[root.step++]
      try {
        now[0]()
      } catch (e) {
        root.check(false, "step " + root.step + " threw: " + e)
      }
      interval = now[1]
      restart()
    }
  }
}
