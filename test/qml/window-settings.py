"""Exercise the production window owner and proxy with offscreen Qt bindings.

Queue, FileView I/O and theme refresh are doubled. No Service, compositor command
or user file is instantiated or changed. check-qml.py separately compiles these
components against the real Quickshell imports.
"""
from pathlib import Path
import shutil
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-window-settings-") as directory:
    root = Path(directory)
    probe = root / "Probe"
    probe.mkdir()
    shutil.copytree(repo / "lib", probe, dirs_exist_ok=True)
    qs = root / "Quickshell"
    io = qs / "Io"
    io.mkdir(parents=True)
    (qs / "qmldir").write_text("module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    (qs / "Quickshell.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property string fixtureText: ""
  property bool fixtureFailure: false
  property int reloads: 0
  function env(name) { return "/isolated" }
}
''')
    (io / "qmldir").write_text("module Quickshell.Io\nFileView 1.0 FileView.qml\n")
    (io / "FileView.qml").write_text('''import QtQuick
import Quickshell
Item {
  property string path: ""
  property bool watchChanges: false
  property bool printErrors: false
  signal loaded()
  signal loadFailed()
  signal fileChanged()
  function text() { return Quickshell.fixtureText }
  function reload() {
    Quickshell.reloads++
    if (Quickshell.fixtureFailure) loadFailed()
    else loaded()
  }
  Component.onCompleted: reload()
}
''')
    (root / "tst_settings.qml").write_text('''import QtQuick
import QtTest
import Quickshell
import "Probe/panel" as PanelUi
import "Probe/windows" as WindowsUi
Item {
  id: host
  width: 1; height: 1
  property var config: ({windows:{innerGap:10,outerGap:10,split:50,rounding:0,speed:1},other:"preserved"})
  property string operation: "idle"
  property int generation: 1
  property string error: ""
  property var queue: []
  property var trace: []
  property int styles: 0
  readonly property bool windowSettingsBusy: settings.windowSettingsBusy
  function snapshot() {
    return JSON.parse(JSON.stringify({windowSettingsBusy:windowSettingsBusy,config:config,
      currentStation:1,draftMode:"extend",draftSingleTarget:"",state:operation,layoutError:error,
      previewSeconds:0,panelEvacuationSerial:0,panelEvacuationFrom:"",panelScreenName:"",
      panelTransferUntil:0,rememberedTab:0,rememberedDisplayName:""}))
  }
  WindowsUi.WindowSettingsController {
    id: settings
    appliedSettings: host.config.windows
    operationState: host.operation
    configGeneration: host.generation
    enqueue: function(command, done, generation) {
      host.trace.push(command[0] === "sh" ? "save" : "read")
      host.queue.push({command:command,done:done,generation:generation})
    }
    publishObserved: function(windows) {
      host.trace.push("publish")
      host.config = Object.assign({},host.config,{windows:windows})
    }
    reportError: function(message) { host.error = message }
    refreshStyle: function() { host.trace.push("style"); host.styles++ }
  }
  PanelUi.BarServiceProxy {
    id: proxy
    api: ({call:function(name,args) { return settings.setWindowSetting(args[0],args[1]) }})
    onSnapshotRefreshRequested: snapshot = host.snapshot()
  }
  TestCase {
    name: "WindowSettingsOwner"
    when: windowShown
    function raw(split) {
      return [{css:"5 5 5 5"},{css:"10 10 10 10"},{float:split},{int:0},{bool:true},
        [[{name:"windows",enabled:true,speed:4}],[]]].map(JSON.stringify).join("\\n\\n")
    }
    function file() {
      for (var i = 0; i < settings.children.length; i++)
        if (settings.children[i].path !== undefined) return settings.children[i]
      fail("owner FileView missing")
    }
    function init() {
      host.queue = []; host.trace = []; host.styles = 0; host.error = ""
      host.operation = "idle"; host.generation = 1
      host.config = {windows:{innerGap:10,outerGap:10,split:50,rounding:0,speed:1},other:"preserved"}
      settings.windowSettingsBusy = false
      Quickshell.fixtureFailure = false; Quickshell.fixtureText = "-- personal Lua\\n"
      file().fileChanged()
      verify(settings.appearanceLoaded)
      compare(settings.appearanceSource,Quickshell.fixtureText)
      proxy.snapshot = host.snapshot()
    }
    function test_proxy_busy_is_synchronous_and_success_readback_authoritative() {
      compare(proxy.setWindowSetting("split",65),"ok")
      verify(host.windowSettingsBusy); verify(proxy.windowSettingsBusy)
      compare(host.queue.length,1); compare(host.queue[0].generation,1)
      compare(host.queue[0].command[4],"/isolated/.config/hypr/looknfeel.lua")
      compare(host.queue[0].command[5],"-- personal Lua\\n")
      verify(host.queue[0].command[6].endsWith("-- personal Lua\\n"))
      var reloads = Quickshell.reloads
      host.queue.shift().done(0,"")
      compare(Quickshell.reloads,reloads+1)
      verify(host.windowSettingsBusy); compare(host.styles,1)
      compare(settings.setWindowSetting("rounding",8),"busy")
      host.queue.shift().done(0,raw(0.7))
      verify(!host.windowSettingsBusy); compare(host.config.windows.split,65)
      compare(host.config.other,"preserved"); compare(host.error,"")
      compare(host.trace.join(","),"save,style,read,publish")
    }
    function test_failures_and_overrides_settle_only_after_readback() {
      for (var i = 0; i < 6; i++) {
        init()
        compare(settings.setWindowSetting("split",65),"ok")
        host.queue.shift().done(i === 1 ? 4 : i === 5 ? 3 : 0,"fixture failure")
        verify(host.windowSettingsBusy)
        if (i === 4) host.generation++
        host.queue.shift().done(i === 2 ? 1 : 0,i === 3 ? "{}" : raw(1))
        verify(!host.windowSettingsBusy)
        compare(host.config.windows.split,50)
        if (i === 0) verify(host.error.indexOf("personal Hyprland rule") >= 0)
        else if (i === 1) verify(host.error.indexOf("Configuration changed") >= 0)
        else if (i === 5) verify(host.error.indexOf("Could not save window setting") >= 0)
        else compare(host.error,"")
        compare(host.styles,i === 1 || i === 5 ? 0 : 1)
      }
    }
    function test_ordinary_reads_cannot_publish_during_save_or_after_generation_change() {
      var completed = null
      settings.refreshWindowSettings(function(ok) { completed = ok })
      compare(settings.setWindowSetting("split",65),"ok")
      host.queue.shift().done(0,raw(0.7))
      compare(completed,false); compare(host.config.windows.split,50)
      settings.refreshWindowSettings(); compare(host.queue.length,1)
      host.queue.shift().done(0,""); host.queue.shift().done(0,raw(0.7))
      settings.refreshWindowSettings(function(ok) { completed = ok })
      host.generation++; host.queue.shift().done(0,raw(1))
      compare(completed,false); compare(host.config.windows.split,65)
    }
    function test_file_callbacks_validation_and_load_gates() {
      settings.appearanceLoaded = false
      compare(settings.setWindowSetting("split",65),"busy")
      Quickshell.fixtureFailure = true; file().fileChanged()
      verify(settings.appearanceLoaded); compare(settings.appearanceSource,"")
      Quickshell.fixtureFailure = false; Quickshell.fixtureText = "-- new personal source\\n"
      file().fileChanged(); compare(settings.appearanceSource,Quickshell.fixtureText)
      compare(settings.setWindowSetting("unknown",1),"invalid")
      compare(settings.setWindowSetting("split","65"),"invalid")
      compare(settings.setWindowSetting("split",Infinity),"invalid")
      host.operation = "previewing"
      compare(settings.setWindowSetting("split",65),"busy")
      host.operation = "idle"
      Quickshell.fixtureText = "-- >>> station windows >>>"; file().fileChanged()
      compare(settings.setWindowSetting("split",65),"invalid")
      verify(!host.windowSettingsBusy); compare(host.queue.length,0)
      verify(host.error.indexOf("markers") >= 0)
    }
    function test_observation_does_not_write_or_refresh_tokens() {
      var before = host.config
      settings.refreshWindowSettings()
      host.queue.shift().done(0,raw(0.7))
      compare(before.windows.split,50); compare(host.config.windows.split,65)
      compare(host.styles,0); verify(!host.windowSettingsBusy)
      compare(host.trace.join(","),"read,publish")
    }
  }
}
''')
    result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-import", str(root), "-input", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME=""),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)
