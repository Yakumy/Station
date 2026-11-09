"""Exercise the production intro handoff against an isolated OWE fixture."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-intro-") as directory:
    root = Path(directory)
    (root / "Wallpaper").symlink_to(repo / "lib/wallpaper")
    cli = root / "owe"
    cli.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys
p = pathlib.Path(os.environ['INTRO_FIXTURE'])
if sys.argv[1] == 'fixture':
    p.write_text(sys.argv[2]); print('{}'); sys.exit()
s = json.loads(p.read_text())
if sys.argv[1] == 'render-status': print(json.dumps(s))
elif sys.argv[1] == 'render':
    r = json.loads(sys.argv[2])
    if r['cmd'] == 'source-rects':
        s['composition_id'] = 9
        s['composition_held'] = True
    else: s['composition_held'] = False
    p.write_text(json.dumps(s))
    print(json.dumps({'status':'ok', 'composition_id':9}))
''')
    cli.chmod(0o755)
    state = root / 'state.json'
    state.write_text('{}')
    (root / 'shell.qml').write_text('''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "Wallpaper" as Wallpaper
ShellRoot {
  Wallpaper.IntroPlayback {
    id: playback
    enabled: false
    themeToken: "one"
    imageWidth: 3840; imageHeight: 2160
    scene: ({mode:"span", followTheme:true, source:"/theme/backgrounds/one.webp", framing:{zoom:2,x:0.2,y:0.8}})
    layout: ({width:1920,height:1080,displays:[{name:"A",identity:"A",x:0,y:0,width:1920,height:1080}]})
  }
  Process {
    id: fixture
    property string value: "{}"
    property bool done: false
    command: ["owe", "fixture", value]
    onExited: done = true
  }
  TestCase {
    name: "IntroPlayback"
    when: true
    function seed(value) {
      fixture.value = JSON.stringify(value); fixture.done = false; fixture.running = true
      tryCompare(fixture, "done", true, 2000)
    }
    function status(extra) {
      return Object.assign({composition_handoff:1,source_rects:1,intro:true,ready:true,media_id:7,
        intro_path:"/theme/backgrounds/intros/one.mp4",composition_id:0,composition_ready:false,error:""},extra || {})
    }
    function test_handoff() {
      seed(status()); playback.enabled = true
      tryCompare(playback, "compositionId", 9, 3000)
      compare(playback.exposed, false) // IPC acceptance alone cannot uncover it.
      seed(status({composition_id:9,composition_ready:true,composition_held:true}))
      tryCompare(playback, "exposed", true, 3000)
      tryCompare(playback, "releaseSent", true, 3000)
      playback.returnReady = false
      seed(status({composition_id:9,composition_ready:true,composition_handoff_pending:true}))
      tryCompare(playback, "returning", true, 3000)
      compare(playback.exposed, false)
      wait(250); compare(playback.finishSent, false)
      playback.returnReady = true
      tryCompare(playback, "finishSent", true, 3000)
      seed(status({intro:false}))
      tryCompare(playback, "exposed", false, 3000)
      // A later theme must rearm after the previous observation stopped.
      playback.themeToken = "two"
      seed(status()); tryCompare(playback, "compositionId", 9, 3000)
      seed(status({composition_id:9,composition_ready:true,composition_held:true}))
      tryCompare(playback, "exposed", true, 3000)
      // A new renderer generation cannot reuse an old crop acknowledgment.
      seed(status({media_id:8,composition_id:1,composition_ready:true}))
      tryCompare(playback, "exposed", false, 3000)
      playback.enabled = false
      seed(status({composition_id:9,composition_ready:true,composition_held:true}))
      wait(250); compare(playback.exposed, false)
      console.log("INTRO_PLAYBACK_PASSED")
    }
    function cleanupTestCase() { Qt.quit() }
  }
}
''')
    result = subprocess.run(['quickshell', '--no-color', '-p', str(root)],
        env=dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'], INTRO_FIXTURE=str(state),
                 QT_QPA_PLATFORM='offscreen'), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    assert 'INTRO_PLAYBACK_PASSED' in result.stdout
    assert not any(error in result.stdout for error in ('FAIL!', 'TypeError', 'ReferenceError', 'Unable to assign'))
