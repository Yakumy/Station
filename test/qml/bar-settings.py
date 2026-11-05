"""Exercise the persistent bar-settings owner offscreen with finite effect ports.

Only theme metrics and host/config/panel effects are doubled. No Station service,
compositor, shell configuration, installation or real bar is instantiated.
"""
from pathlib import Path
import shutil
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-bar-settings-") as directory:
    root = Path(directory)
    probe = root / "Probe"
    probe.mkdir()
    shutil.copytree(repo / "lib", probe, dirs_exist_ok=True)
    commons = root / "qs" / "Commons"
    commons.mkdir(parents=True)
    (commons / "qmldir").write_text("module qs.Commons\nsingleton Style 1.0 Style.qml\n")
    (commons / "Style.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var font: ({body: 12})
  property var bar: ({sizeHorizontal: 26, sizeVertical: 26})
  property var spacing: ({sm: 4})
}
''')
    (root / "tst_settings.qml").write_text('''import QtQuick
import QtTest
import "Probe/bars" as Bars
Item {
  id: host
  width: 1; height: 1
  property var preferences: ({})
  property var config: null
  property bool ready: false
  property bool panelOpen: true
  property bool rejectPublish: false
  property int saves: 0
  property int publishes: 0
  property int retains: 0
  property string retainedTab: ""
  property int layers: 0
  Bars.BarSettingsController {
    id: settings
    preferences: host.preferences
    hostConfig: host.config
    configLoaded: host.ready
    panelWanted: host.panelOpen
    focusedBarScreenName: "A"
    displays: [{name:"A",enabled:true,width:1920,height:1080},
      {name:"B",enabled:true,width:1920,height:1080}]
    persistPreferences: function(rows) { host.preferences = rows; host.saves++ }
    publishHost: function(change) {
      if (host.rejectPublish) return false
      var next = JSON.parse(JSON.stringify(host.config))
      change(next); host.config = next; host.publishes++
      return true
    }
    retainPanel: function(tab) { host.retainedTab = tab; host.retains++ }
    requestLayerSync: function() { host.layers++ }
  }
  TestCase {
    name: "BarSettingsOwner"
    when: windowShown
    function init() {
      host.ready = false; host.panelOpen = true; host.rejectPublish = false
      host.preferences = {A:{enabled:true,position:"top",width:100},B:{enabled:true,position:"top",width:100}}
      host.config = {bar:{id:"yakumy.station",position:"top",
        monitors:JSON.parse(JSON.stringify(host.preferences)),
        layout:{left:[{id:"omarchy.menu"},{id:"yakumy.station"}],center:[],right:[]}}}
      settings.pendingMonitorBars = {}; settings.observedHostBars = {}
      settings.monitorBarMinimums = {}; settings.monitorBarMaximumContents = {}
      settings.lastGlobalBarPosition = "top"
      wait(0)
      host.ready = true; wait(0)
      host.saves = 0; host.publishes = 0; host.retains = 0; host.layers = 0
    }
    function test_deferred_edit_and_close() {
      var before = host.preferences
      compare(settings.setMonitorBarWidth("A",45),"ok")
      compare(settings.setMonitorBarWidth("B",55),"ok")
      compare(before.A.width,100)
      compare(settings.monitorBar("A").width,45)
      compare(host.publishes,0); compare(host.retains,2); compare(host.retainedTab,"bar")
      host.panelOpen = false; settings.panelClosed()
      tryCompare(host,"publishes",1)
      compare(host.config.bar.monitors.A.width,45)
      compare(host.config.bar.monitors.B.width,55)
      compare(Object.keys(settings.pendingMonitorBars).length,0)
      compare(host.config.bar.layout.left.length,1)
      compare(host.config.bar.layout.left[0].id,"omarchy.menu")
    }
    function test_external_rows_supersede_independently() {
      compare(settings.setMonitorBarWidth("A",45),"ok")
      compare(settings.setMonitorBarWidth("B",55),"ok")
      var next = JSON.parse(JSON.stringify(host.config))
      next.bar.monitors.A.position = "right"; next.bar.monitors.A.width = 80
      host.config = next
      tryCompare(settings,"hostBarsSignature",JSON.stringify(next.bar.monitors))
      tryVerify(function() { return settings.monitorBar("A").position === "right" })
      compare(settings.pendingMonitorBars.A,undefined)
      compare(settings.pendingMonitorBars.B.width,55)
      compare(settings.monitorBar("B").width,55)
    }
    function test_failed_publish_retains_pending() {
      compare(settings.setMonitorBarWidth("A",45),"ok")
      host.panelOpen = false; host.rejectPublish = true
      compare(settings.flushPendingMonitorBars(),false)
      compare(settings.pendingMonitorBars.A.width,45)
      host.rejectPublish = false
      compare(settings.flushPendingMonitorBars(),true)
      compare(Object.keys(settings.pendingMonitorBars).length,0)
    }
    function test_limits_are_transient_and_last_bar_survives() {
      compare(settings.reportMonitorBarMinimum("A",55),"ok")
      compare(settings.reportMonitorBarMaximumContent("A",17),"ok")
      compare(settings.monitorBarMinimum("A"),55)
      compare(settings.monitorBarMaximumContent("A"),17)
      compare(host.saves,0)
      compare(host.preferences.A.minimum,undefined)
      compare(settings.setMonitorBarEnabled("A",false),"ok")
      compare(host.layers,1)
      compare(settings.setMonitorBarEnabled("B",false),"last-bar")
      compare(settings.setMonitorBarWidth("../bad",50),"invalid")
    }
    function test_load_gate_adopts_late_host_state() {
      host.ready = false
      var next = JSON.parse(JSON.stringify(host.config))
      next.bar.monitors.A.position = "right"
      host.config = next; wait(0)
      compare(settings.monitorBar("A").position,"top")
      host.ready = true
      tryVerify(function() { return settings.monitorBar("A").position === "right" })
    }
  }
}
''')
    result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-import", str(root), "-input", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME=""),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)
