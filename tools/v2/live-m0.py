"""Staged, reversible M0 platform experiment; not Station runtime code."""
import json, os, re, shutil, signal, socket, subprocess, sys, time, threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SESSION = Path('/tmp') / ('station-v2-m0-' + str(os.getuid()))
HOME = Path.home()
PLUGIN = HOME / '.config/omarchy/plugins/yakumy.station-m0'
STATE = HOME / '.local/state/omarchy/station-m0'
MONITORS = HOME / '.config/hypr/monitors.lua'
ID = 'yakumy.station-m0'

def cmd(*args, check=True):
    p = subprocess.run(args, text=True, capture_output=True, timeout=30)
    if check and p.returncode:
        raise RuntimeError(str(args[:2]) + ': ' + p.stderr + p.stdout)
    return p.stdout.strip()

def js(*args): return json.loads(cmd(*args))
def ipc(method, *args): return cmd('omarchy-shell', ID, method, *args)
def status(): return json.loads(ipc('status'))
def wait(fn, seconds=15):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            value = fn()
            if value: return value
        except (RuntimeError, ValueError): pass
        time.sleep(.15)
    raise RuntimeError('Timed out waiting for probe condition')

def save(name, value):
    (SESSION / (name + '.json')).write_text(json.dumps(value, indent=2)+'\n')
    print(name + ': ' + json.dumps(value), flush=True)

def baseline(): return json.loads((SESSION/'baseline.json').read_text())
def lua(code):
    result = cmd('hyprctl', 'eval', code)
    if result != 'ok': raise RuntimeError('Lua: '+result)

def reload():
    cmd('hyprctl','reload')
    time.sleep(.5)
    errors = cmd('hyprctl','configerrors')
    if errors: raise RuntimeError(errors)

def restore_focus():
    base = baseline()
    parts = []
    names = {m['id']: m['name'] for m in base['monitors']}
    places = {c['workspace']['id']: names[c['monitor']] for c in base['clients']
              if c['workspace']['id'] > 0 and c['monitor'] in names}
    current = {w['id']: w['monitor'] for w in js('hyprctl','workspaces','-j')}
    for wid, name in places.items():
        if wid in current and current[wid] != name:
            parts.append('hl.dispatch(hl.dsp.workspace.move({ workspace = '+json.dumps(str(wid))+', monitor = '+json.dumps(name)+' }))')
    for m in base['monitors']:
        parts.append('hl.dispatch(hl.dsp.focus({ workspace = '+json.dumps(str(m['activeWorkspace']['id']))+' }))')
    focused = next(m['name'] for m in base['monitors'] if m['focused'])
    parts.append('hl.dispatch(hl.dsp.focus({ monitor = '+json.dumps(focused)+' }))')
    lua('; '.join(parts))

def install():
    if SESSION.exists() or PLUGIN.exists() or STATE.exists():
        raise RuntimeError('Refusing to overwrite an existing M0 session/plugin/state')
    if MONITORS.is_symlink(): raise RuntimeError('monitors.lua is a symlink')
    if cmd('hyprctl','configerrors'): raise RuntimeError('Existing config errors')
    SESSION.mkdir(mode=0o700)
    STATE.mkdir(mode=0o700, parents=True)
    shutil.copy2(MONITORS, SESSION/'monitors.lua.original')
    shellfile = HOME / '.config/omarchy/shell.json'
    if shellfile.exists(): shutil.copy2(shellfile, SESSION/'shell.json.original')
    mons=js('hyprctl','monitors','-j')
    clients=js('hyprctl','clients','-j')
    # This fixture uses existing grid workspaces, never moves a client.
    if any(m['activeWorkspace']['id'] not in [1,2,3] for m in mons):
        raise RuntimeError('Fixture requires current workspaces in station 1')
    base={'monitors':mons,'shell':js('omarchy-shell','shell','listShellConfig'),
          'clients':[{'address':c['address'],'workspace':c['workspace'],'monitor':c['monitor']} for c in clients]}
    (SESSION/'baseline.json').write_text(json.dumps(base,indent=2)+'\n')
    config={'armed':False,'outputs':[{'name':m['name'],'lane':m['activeWorkspace']['id']} for m in mons],
            'focus':next(m['name'] for m in mons if m['focused'])}
    for m in mons:
        if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,64}',m['name']): raise RuntimeError('Bad connector')
    (STATE/'probe.json').write_text(json.dumps(config))
    shutil.copytree(ROOT/'tools/v2/m0-plugin',PLUGIN)
    cmd('omarchy-shell','shell','rescanPlugins')
    wait(lambda: any(p['id']==ID for p in js('omarchy-shell','shell','listPlugins')))
    cmd('omarchy','plugin','enable',ID,'--section','left','--index','1')
    wait(lambda: status())
    result=ipc('probe','2')
    assert result.startswith('service:2:')
    assert ipc('probe','11') == 'invalid'
    save('installed',{'closedPanelIPC':result,'state':status(), 'config':js('omarchy-shell','shell','listShellConfig')})

def sync():
    PLUGIN.mkdir(parents=True, exist_ok=True)
    for source in (ROOT/'tools/v2/m0-plugin').iterdir():
        if source.is_file(): shutil.copy2(source, PLUGIN/source.name)
    cmd('omarchy-shell','shell','rescanPlugins')
    time.sleep(1)
    if not enabled(ID): cmd('omarchy','plugin','enable',ID,'--section','left','--index','1')
    cmd('omarchy','restart','shell')
    wait(lambda: status())

def ui():
    before=status()
    if before['panel']['opened']: ipc('togglePanel'); time.sleep(.4)
    result=ipc('togglePanel')
    shown=wait(lambda: (s if (s:=status())['panel'].get('opened') and s['panel'].get('focused') else None))
    save('popout-open',shown)
    cmd('wtype','-k','Escape')
    hidden=wait(lambda: not status()['panel']['opened'])
    save('popout-escape',{'closed':hidden,'serviceOpenReturn':result})

def arm():
    if any(c['workspace']['id'] in [25,26,27,28,29,30] for c in js('hyprctl','clients','-j')):
        raise RuntimeError('Reserved probe stations contain clients')
    config=json.loads((STATE/'probe.json').read_text()); config['armed']=True
    (STATE/'probe.json').write_text(json.dumps(config))
    wait(lambda: len([b for b in js('hyprctl','binds','-j') if b.get('description','').startswith('Station: M0')])==3)
    wait(lambda: not status()['busy'])
    assert ipc('switchProbe','2')=='started'
    wait(lambda: not status()['busy'])
    mons=js('hyprctl','monitors','-j')
    lanes={m['name']:m['lane'] for m in config['outputs']}
    assert all(m['activeWorkspace']['id']==27+lanes[m['name']] for m in mons)
    assert next(m['name'] for m in mons if m['focused'])==config['focus']
    assert ipc('switchProbe','1')=='started'
    wait(lambda: not status()['busy'])
    save('focus-batch',{'passed':True,'status':status()})
    # Virtual-keyboard input traverses compositor bindings and real service IPC.
    # Wall time includes wtype process startup and snapshot polling overhead.
    samples=[]
    for i in range(20):
        n=2 if i%2==0 else 1
        initial=status()['calls']
        start=time.monotonic()
        cmd('wtype','-M','ctrl','-M','logo','-s','50','-k','Right' if n==2 else 'Left','-s','50','-m','logo','-m','ctrl')
        def done():
            ms=js('hyprctl','monitors','-j')
            return all(m['activeWorkspace']['id']==(n+7)*3+lanes[m['name']] for m in ms)
        wait(done,3)
        elapsed=(time.monotonic()-start)*1000
        end=status(); assert end['calls']==initial+1
        samples.append(elapsed)
    ordered=sorted(samples)
    save('key-latency',{'samplesMs':samples,'p50Ms':ordered[9],'p95Ms':ordered[18],
        'method':'wtype virtual key -> compositor binding -> shell IPC -> service -> eval -> hyprctl snapshot; includes launcher/poll overhead'})
    restore_focus()

def restart():
    before=js('hyprctl','binds','-j')
    cmd('omarchy','restart','shell')
    wait(lambda: status(),30)
    wait(lambda: not status()['busy'])
    after=js('hyprctl','binds','-j')
    own=[b for b in after if b.get('description','').startswith('Station: M0')]
    assert len(own)==3
    save('restart',{'before':len([b for b in before if b.get('description','').startswith('Station: M0')]),
         'after':len(own),'lifecycle':(STATE/'lifecycle.log').read_text()})

def diagnose():
    print(status())
    print([(m["name"],m["activeWorkspace"]["id"]) for m in js("hyprctl","monitors","-j")])
    print(cmd("hyprctl","workspacerules","-j"))
    restore_focus()

def latency():
    if not enabled(ID):
        sync()
    config=setconfig(armed=True)
    wait(lambda: len([b for b in js('hyprctl','binds','-j') if b.get('description','').startswith('Station: M0')])==3)
    samples=[]
    for i in range(20):
        expected='2' if i%2==0 else '1'
        before=status()
        start=time.monotonic()
        cmd('wtype','-M','ctrl','-M','logo','-s','30','-k','Right' if expected=='2' else 'Left','-s','30','-m','logo','-m','ctrl')
        result=wait(lambda: (s if (s:=status())['completed']>before['completed'] and s['calls']>before['calls'] else None),3)
        elapsed=(time.monotonic()-start)*1000
        if result['lastSwitch'] != expected:
            raise RuntimeError('Virtual key routed to '+result['lastSwitch']+' instead of '+expected)
        samples.append(elapsed)
    ordered=sorted(samples)
    save('key-latency',{'samplesMs':samples,'p50Ms':ordered[9],'p95Ms':ordered[18],
        'method':'wtype virtual key -> compositor bind -> omarchy-shell IPC -> service -> hyprctl eval completion'})
    restore_focus()

def manual_prepare():
    SESSION.mkdir(mode=0o700, exist_ok=True)
    mons=js('hyprctl','monitors','-j')
    if not (SESSION/'baseline.json').exists():
        clients=js('hyprctl','clients','-j')
        (SESSION/'baseline.json').write_text(json.dumps({'monitors':mons,
          'shell':js('omarchy-shell','shell','listShellConfig'),
          'clients':[{'address':c['address'],'workspace':c['workspace'],'monitor':c['monitor']} for c in clients]},indent=2)+'\n')
        (SESSION/'monitors.lua.original').write_bytes(MONITORS.read_bytes())
    if not enabled(ID): sync()
    setconfig(armed=True,
      outputs=[{'name':m['name'],'lane':m['activeWorkspace']['id']} for m in mons],
      focus=next(m['name'] for m in mons if m['focused']),
      returnWorkspace=next(m['activeWorkspace']['id'] for m in mons if m['focused']),
      lease={'section':'left','index':0,'restore':False})
    wait(lambda: len([b for b in js('hyprctl','binds','-j') if b.get('description','').startswith('Station: M0')])==3)
    assert ipc('resetTimings')=='ok'
    if status()['panel'].get('opened'): ipc('togglePanel'); time.sleep(.3)
    ipc('togglePanel')
    wait(lambda: status()['panel'].get('opened') and status()['panel'].get('focused'))
    save('manual-prepared',status())

def manual_finish():
    result=status()
    if result['panel'].get('opened'):
        raise RuntimeError('Popout is still open; outside-click check did not complete')
    samples=result.get('timingsMs',[])
    if len(samples)!=20:
        raise RuntimeError('Expected 20 physical key samples, got '+str(len(samples)))
    ordered=sorted(samples)
    save('physical-key-latency',{'samplesMs':samples,'p50Ms':ordered[9],'p95Ms':ordered[18],
        'method':'physical key -> compositor bind -> timestamp wrapper -> omarchy-shell IPC -> service -> hyprctl eval completion'})
    restore_focus()

def setconfig(**values):
    config=json.loads((STATE/'probe.json').read_text()); config.update(values)
    (STATE/'probe.json').write_text(json.dumps(config))
    wait(lambda: all(status().get('config',{}).get(k)==v for k,v in values.items()))
    return config

def monitor_rule(m, **overrides):
    fields={'output':m['name'], 'mode':m['availableModes'][0],
            'position':str(m['x'])+'x'+str(m['y']), 'scale':m['scale'],
            'transform':m['transform'], 'disabled':False, 'mirror':''}
    fields.update(overrides)
    return 'hl.monitor({ '+', '.join(k+' = '+json.dumps(v) for k,v in fields.items())+' })'

def effects():
    setconfig(armed=False)
    base=baseline()['monitors']; target=base[0]; other=base[1]
    path=Path(os.environ['XDG_RUNTIME_DIR'])/'hypr'/os.environ['HYPRLAND_INSTANCE_SIGNATURE']/'.socket2.sock'
    events=[]; phase=['starting']; stopping=threading.Event()
    sock=socket.socket(socket.AF_UNIX); sock.connect(str(path)); sock.settimeout(.1)
    start=time.monotonic()
    def capture():
        buf=b''
        while not stopping.is_set():
            try: data=sock.recv(65536)
            except socket.timeout: continue
            if not data: break
            buf+=data
            while b'\n' in buf:
                line,buf=buf.split(b'\n',1)
                name,_,body=line.decode(errors='replace').partition('>>')
                if name.startswith(('monitor','workspace','focusedmon','configreloaded')):
                    events.append({'ms':round((time.monotonic()-start)*1000,2),'phase':phase[0],'kind':name,'data':body})
    thread=threading.Thread(target=capture); thread.start()
    try:
        phase[0]='exact-mode-with-Hz'
        lua(monitor_rule(target)); time.sleep(.3)
        actual=next(m for m in js('hyprctl','monitors','-j') if m['name']==target['name'])
        assert actual['width']==target['width'] and actual['height']==target['height']
        assert abs(actual['refreshRate']-target['refreshRate'])<.1
        save('mode-spelling',{'accepted':target['availableModes'][0], 'configErrors':cmd('hyprctl','configerrors')})
        phase[0]='runtime-precedence'
        lua(monitor_rule(target,position='10x'+str(target['y']))+'; '+monitor_rule(target,position='20x'+str(target['y'])))
        time.sleep(.3)
        assert next(m for m in js('hyprctl','monitors','-j') if m['name']==target['name'])['x']==20
        phase[0]='file-precedence'
        original=(SESSION/'monitors.lua.original').read_text()
        text=original+'\n-- >>> station-m0 >>>\n'+monitor_rule(target,position='10x'+str(target['y']))+'\n'+monitor_rule(target,position='20x'+str(target['y']))+'\n-- <<< station-m0 <<<\n'
        MONITORS.write_text(text); reload()
        assert next(m for m in js('hyprctl','monitors','-j') if m['name']==target['name'])['x']==20
        save('rule-precedence',{'runtimeLastWins':True,'fileLastWins':True})
        MONITORS.write_text(original); reload()
        phase[0]='self-disable'; lua(monitor_rule(target,disabled=True)); time.sleep(.5)
        assert len(js('hyprctl','monitors','-j'))==len(base)-1
        phase[0]='self-enable'; lua(monitor_rule(target)); time.sleep(.5)
        phase[0]='self-mirror'; lua(monitor_rule(target,mirror=other['name'])); time.sleep(.5)
        phase[0]='clear-mirror'; lua(monitor_rule(target)); time.sleep(.5)
        assert next(m for m in js('hyprctl','monitors','all','-j') if m['name']==target['name'])['mirrorOf']=='none'
    finally:
        MONITORS.write_bytes((SESSION/'monitors.lua.original').read_bytes())
        phase[0]='restore'; reload(); restore_focus()
        stopping.set(); thread.join(); sock.close()
        save('effect-events',events)

def crash():
    setconfig(armed=False)
    base=baseline()['monitors']; target=base[0]
    # Detached backstop survives this runner too; fixture watchdog is the object
    # under test, while this later fallback only limits a failed experiment.
    guard=subprocess.Popen(['sh','-c','sleep 35; hyprctl reload'],start_new_session=True,
                           stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        (STATE/'preview.token').write_text('m0\n')
        assert ipc('watchdog')=='armed'
        lua(monitor_rule(target,position='10x'+str(target['y'])))
        instances=js('quickshell','list','-p','/usr/share/omarchy/shell','-j')
        assert len(instances)==1 and instances[0]['config_path']=='/usr/share/omarchy/shell/shell.qml'
        if subprocess.run(['omarchy-hyprland-session-locked'],stdout=subprocess.DEVNULL).returncode==0:
            raise RuntimeError('Session locked; not killing shell')
        start=time.monotonic(); os.kill(instances[0]['pid'],signal.SIGKILL)
        wait(lambda: not (STATE/'preview.token').exists(),25)
        elapsed=time.monotonic()-start
        wait(lambda: next(m for m in js('hyprctl','monitors','-j') if m['name']==target['name'])['x']==target['x'])
        wait(lambda: status(),30)
        save('crash-watchdog',{'killedPid':instances[0]['pid'],'rollbackSeconds':elapsed,'tokenRemoved':True,
              'geometryRestored':True,'shellReturned':True})
    finally:
        os.killpg(guard.pid,signal.SIGTERM); guard.wait()
        (STATE/'preview.token').unlink(missing_ok=True)
        reload(); restore_focus()

def location(config, widget):
    for section, entries in config['bar']['layout'].items():
        for index, entry in enumerate(entries):
            if (entry.get('id') if isinstance(entry,dict) else entry)==widget:
                return {'section':section,'index':index}
    return None

def enabled(widget):
    return next((p['enabled'] for p in js('omarchy-shell','shell','listPlugins') if p['id']==widget),False)

def lease_remove():
    if not enabled(ID):
        cmd('omarchy','plugin','enable',ID,'--section','left','--index','1'); wait(lambda:status())
    original_location=location(baseline()['shell'],'omarchy.workspaces')
    original_enabled=original_location is not None
    try:
        # Already-disabled stock widget must stay disabled after destruction.
        setconfig(armed=False,lease={'section':'left','index':0,'restore':False})
        cmd('omarchy','plugin','disable','omarchy.workspaces')
        cmd('omarchy','plugin','disable',ID)
        time.sleep(5)
        assert not enabled('omarchy.workspaces')
        save('already-disabled-lease',{'stayedDisabled':True,'lifecycle':(STATE/'lifecycle.log').read_text()})
        cmd('omarchy','plugin','enable',ID,'--section','left','--index','1'); wait(lambda: status())
        # Move native widget before acquisition; cleanup must restore this NEW place.
        cmd('omarchy','plugin','enable','omarchy.workspaces')
        cmd('omarchy','bar','move','omarchy.workspaces','--section','right','--index','1')
        lease={'section':'right','index':1}
        wait(lambda: location(js('omarchy-shell','shell','listShellConfig'),'omarchy.workspaces')==lease)
        setconfig(armed=True,lease={**lease,'restore':True})
        cmd('omarchy','plugin','disable','omarchy.workspaces')
        wait(lambda: len([b for b in js('hyprctl','binds','-j') if b.get('description','').startswith('Station: M0')])==3)
        cmd('omarchy','restart','shell'); wait(lambda: status(),30); time.sleep(4)
        assert not enabled('omarchy.workspaces')
        assert len([b for b in js('hyprctl','binds','-j') if b.get('description','').startswith('Station: M0')])==3
        save('restart-with-lease',{'stockStillHidden':True,'ownBinds':3,'lifecycle':(STATE/'lifecycle.log').read_text()})
        mons=baseline()['monitors']; target=mons[1]; off=mons[0]
        plain='\n'.join(monitor_rule(m).replace(', disabled = false, mirror = ""','') for m in mons)+'\n'
        (STATE/'monitors-block.plain.lua').write_text(plain)
        guard='local up = {}\nif type(hl.get_monitors) == "function" then\n local ok, list = pcall(hl.get_monitors)\n if ok and type(list) == "table" then for _, m in ipairs(list) do\n  local ok2, name = pcall(function() return m.name end)\n  if ok2 and type(name) == "string" then up[name] = true end\n end end\nend\n'
        disable='if up['+json.dumps(target['name'])+'] then hl.monitor({ output = '+json.dumps(off['name'])+', disabled = true }) end\n'
        def single():
            MONITORS.write_text((SESSION/'monitors.lua.original').read_text()+'\n-- >>> station-m0 >>>\n'+guard+plain+disable+'-- <<< station-m0 <<<\n')
            reload(); wait(lambda:len(js('hyprctl','monitors','-j'))==1)
        single()
        start=time.monotonic()
        cmd('omarchy','plugin','disable',ID)
        wait(lambda: len(js('hyprctl','monitors','-j'))==len(mons),12)
        wait(lambda:enabled('omarchy.workspaces'))
        assert location(js('omarchy-shell','shell','listShellConfig'),'omarchy.workspaces')==lease
        block=MONITORS.read_text().split('-- >>> station-m0 >>>\n')[1].split('-- <<< station-m0 <<<')[0]
        assert block==plain
        assert not [b for b in js('hyprctl','binds','-j') if b.get('description','').startswith('Station: M0')]
        save('disable-cleanup',{'seconds':time.monotonic()-start,'plainBlock':True,'allMonitors':True,'lease':lease,'ownBinds':0})
        # Re-enable; acquire again; remove directly while Single is saved.
        cmd('omarchy','plugin','enable',ID,'--section','left','--index','1'); wait(lambda:status())
        cmd('omarchy','plugin','disable','omarchy.workspaces')
        single()
        start=time.monotonic()
        result=cmd('omarchy','plugin','remove',ID,'--yes')
        wait(lambda: len(js('hyprctl','monitors','-j'))==len(mons),12)
        wait(lambda:enabled('omarchy.workspaces'))
        assert location(js('omarchy-shell','shell','listShellConfig'),'omarchy.workspaces')==lease
        block=MONITORS.read_text().split('-- >>> station-m0 >>>\n')[1].split('-- <<< station-m0 <<<')[0]
        assert block==plain
        binds=js('hyprctl','binds','-j')
        assert not [b for b in binds if b.get('description','').startswith('Station: M0')]
        descriptions={b.get('description') for b in binds}
        assert 'Switch to workspace 1' in descriptions
        assert 'Move grouped window focus left' in descriptions
        save('remove-cleanup',{'seconds':time.monotonic()-start,'plainBlock':True,'allMonitors':True,'lease':lease,
             'ownBinds':0,'defaultDescriptionsRestored':True,'removeOutput':result,'lifecycle':(STATE/'lifecycle.log').read_text()})
    finally:
        if PLUGIN.exists(): cmd('omarchy','plugin','disable',ID,check=False); time.sleep(4)
        if original_enabled:
            cmd('omarchy','plugin','enable','omarchy.workspaces')
            cmd('omarchy','bar','move','omarchy.workspaces','--section',original_location['section'],'--index',str(original_location['index']))
        else: cmd('omarchy','plugin','disable','omarchy.workspaces')
        MONITORS.write_bytes((SESSION/'monitors.lua.original').read_bytes()); reload(); restore_focus()

def cleanup():
    if not SESSION.exists(): return
    if PLUGIN.exists(): cmd('omarchy','plugin','remove',ID,'--yes')
    # The runner's backstop reload is NOT evidence that plugin cleanup works.
    if MONITORS.read_bytes() != (SESSION/'monitors.lua.original').read_bytes():
        shutil.copy2(SESSION/'monitors.lua.original',MONITORS)
    reload(); restore_focus()
    own=[b for b in js('hyprctl','binds','-j') if b.get('description','').startswith('Station: M0')]
    save('runner-restored',{'ownBindings':len(own),'configErrors':cmd('hyprctl','configerrors'),
         'lifecycle':(STATE/'lifecycle.log').read_text() if (STATE/'lifecycle.log').exists() else ''})

if __name__=='__main__':
    try:
        {'install':install,'sync':sync,'ui':ui,'arm':arm,'restart':restart,'cleanup':cleanup,
         'diagnose':diagnose,'latency':latency,'manual-prepare':manual_prepare,'manual-finish':manual_finish,
         'effects':effects,'crash':crash,'lease-remove':lease_remove}[sys.argv[1]]()
    except Exception:
        if (SESSION/'baseline.json').exists(): restore_focus()
        raise
