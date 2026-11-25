"""Hover and drag the shared ScrollThumb with real pointer events.

Renders an overflowing ListView with the thumb over it in an isolated window, then
uses QtTest's TestEvent to hover, press, drag and leave. It checks that the thumb
travels the middle 80% of the list, shows only while the pointer is on it, takes the
press away from the rows under it, and moves the list with the pointer. It then
shows hinted lists: the first with a key peeks and returns with the thumb shown, a
second with the same key stays still, and reduced motion skips the hint without
using up its key. No Station service, compositor command or installed file is touched.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "test/helpers"))
import wayland  # noqa: E402

wayland.require("Scroll-thumb check")

QML = r'''import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "Station/panel" as PanelUi
ShellRoot {
  FloatingWindow {
    id: win
    implicitWidth: 900; implicitHeight: 200; visible: true
    component Rows: ListView {
      anchors.fill: parent
      model: 10
      delegate: Item {
        required property int index
        width: ListView.view.width; height: 32
        MouseArea { anchors.fill: parent; onPressed: report.rowPresses++ }
      }
    }
    Item {
      id: box
      width: 200; height: 160
      Rows { id: list }
      PanelUi.ScrollThumb { id: thumb; flickable: list }
    }
    // Two lists that share one hint key, and one under reduced motion. Omarchy's
    // Style rereads its motion toggle on Hyprland events, so the calm thumb sets its own.
    Item {
      id: firstBox; x: 220; width: 200; height: 160; visible: false
      Rows { id: firstList }
      PanelUi.ScrollThumb { id: firstThumb; flickable: firstList; hintKey: "probe" }
    }
    Item {
      id: secondBox; x: 440; width: 200; height: 160; visible: false
      Rows { id: secondList }
      PanelUi.ScrollThumb { flickable: secondList; hintKey: "probe" }
    }
    Item {
      id: calmBox; x: 660; width: 200; height: 160; visible: false
      Rows { id: calmList }
      PanelUi.ScrollThumb { id: calmThumb; flickable: calmList; hintKey: "calm"; reduceMotion: true }
    }
    QtObject {
      id: report
      property int rowPresses: 0
      property var failures: []
      property real firstPeak: 0
      property real secondPeak: 0
      property real calmPeak: 0
      property bool firstShown: false
      function check(ok, what) { if (!ok) failures.push(what) }
      function near(a, b) { return Math.abs(a - b) < 0.5 }
      // Stop at once rather than leave the shell running to the harness timeout.
      function fail(what) { console.log("SCROLL_THUMB_FAILED " + what); Qt.quit() }
    }
    Connections { target: firstList; function onContentYChanged() { report.firstPeak = Math.max(report.firstPeak, firstList.contentY); if (firstThumb.shown) report.firstShown = true } }
    Connections { target: secondList; function onContentYChanged() { report.secondPeak = Math.max(report.secondPeak, secondList.contentY) } }
    Connections { target: calmList; function onContentYChanged() { report.calmPeak = Math.max(report.calmPeak, calmList.contentY) } }
    TestEvent { id: pointer }

    // Start once the window is shown and laid out, not after a fixed delay.
    Timer {
      id: settle
      interval: 50; repeat: true; running: true
      property int tries: 0
      onTriggered: {
        if (++tries < 100 && !(box.Window.window && box.Window.window.visible && list.height > 0
            && list.contentHeight > list.height && thumb.height > 0)) return
        settle.stop()
        try { win.drag() } catch (error) { report.fail("drag threw " + error) }
        // The hint: first show plays it, a second list with the same key does not,
        // and reduced motion skips it.
        calmBox.visible = true
        afterReduced.start()
      }
    }
    Timer {
      id: afterReduced
      interval: 800
      onTriggered: {
        report.check(report.calmPeak === 0, "the hint plays under reduced motion")
        calmThumb.reduceMotion = false
        firstBox.visible = true
        afterFirst.start()
      }
    }
    function drag() {
      var check = report.check, near = report.near
      var line = thumb.children[thumb.children.length - 1]
      check(thumb.visible, "thumb hidden on an overflowing list")
      check(near(thumb.track, list.height * 0.8), "track is not 80% of the list")
      check(near(thumb.y, list.height * 0.1), "thumb does not start 10% down")
      check(line.opacity === 0, "thumb shows before it is hovered")
      check(!thumb.shown, "a thumb with no hint key plays the hint")

      // A real pointer stays put in the window while the thumb moves under it.
      var cx = thumb.x + thumb.width / 2, cy = thumb.y + thumb.height / 2
      pointer.mouseMove(box, 20, cy, -1, Qt.NoButton, 0)
      check(!thumb.shown, "hovering the list away from the thumb shows it")
      pointer.mouseMove(box, cx, cy, -1, Qt.NoButton, 0)
      check(thumb.shown, "hovering the thumb does not show it")

      pointer.mousePress(box, cx, cy, Qt.LeftButton, Qt.NoModifier, -1)
      check(report.rowPresses === 0, "the press reached the row under the thumb")
      pointer.mouseMove(box, cx, cy + 20, -1, Qt.LeftButton, 0)
      pointer.mouseMove(box, cx, cy + 40, -1, Qt.LeftButton, 0)
      check(near(list.contentY, 40 * list.contentHeight / thumb.track), "dragging does not move the list with the pointer")
      check(near(thumb.y + thumb.height / 2, cy + 40), "the thumb does not follow the pointer")
      check(thumb.shown, "the thumb hides mid-drag")
      pointer.mouseMove(box, cx, cy + 400, -1, Qt.LeftButton, 0)
      check(near(list.contentY, list.contentHeight - list.height), "dragging past the end does not stop at the last row")
      check(thumb.y + thumb.height <= thumb.trackTop + thumb.track + 0.5, "the thumb leaves its track")
      pointer.mouseRelease(box, cx, cy + 400, Qt.LeftButton, Qt.NoModifier, -1)
      pointer.mouseMove(box, 20, 20, -1, Qt.NoButton, 0)
      check(!thumb.shown, "the thumb stays after the pointer leaves")
    }
    Timer {
      id: afterFirst
      interval: 1400
      onTriggered: {
        report.check(report.firstPeak > 20, "the first overflowing list does not peek (peak " + report.firstPeak + ")")
        report.check(report.firstShown, "the thumb is not shown while the list peeks")
        report.check(report.near(firstList.contentY, 0), "the peek does not return to the top")
        secondBox.visible = true
        firstBox.visible = false
        firstBox.visible = true
        afterSecond.start()
      }
    }
    Timer {
      id: afterSecond
      interval: 1400
      onTriggered: {
        report.check(report.secondPeak === 0, "a second list with the same key peeks again")
        report.check(report.near(firstList.contentY, 0), "showing a list again replays its hint")
        // Reduced motion did not use up its key: the next show plays it.
        calmBox.visible = false
        calmBox.visible = true
        afterCalm.start()
      }
    }
    Timer {
      id: afterCalm
      interval: 1400
      onTriggered: {
        report.check(report.calmPeak > 20, "reduced motion used up the hint")
        var failures = report.failures
        console.log(failures.length ? "SCROLL_THUMB_FAILED " + failures.join("; ") : "SCROLL_THUMB_OK")
        Qt.quit()
      }
    }
  }
}
'''

with tempfile.TemporaryDirectory(prefix="station-scroll-thumb-probe-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    (root / "Station").symlink_to(repo / "lib", target_is_directory=True)
    (root / "shell.qml").write_text(QML)
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    if "SCROLL_THUMB_OK" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign")):
        sys.exit(1)
