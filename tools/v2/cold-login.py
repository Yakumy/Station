"""Install/remove an observational cold-login probe; never disables a display."""
import json, os, re, subprocess, sys, tempfile, time
from pathlib import Path

HOME = Path.home()
CONFIG = HOME / '.config/hypr/monitors.lua'
STATE = HOME / '.local/state/omarchy/station-m0-cold'
BEGIN = '-- >>> station-m0-cold (observation only) >>>'
END = '-- <<< station-m0-cold <<<'

def command(*args):
    p = subprocess.run(args, text=True, capture_output=True, timeout=10)
    if p.returncode: raise RuntimeError(p.stderr or p.stdout)
    return p.stdout.strip()

def atomic(path, text):
    if path.is_symlink(): raise RuntimeError('Refusing symlink: '+str(path))
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix='.station-m0-', dir=path.parent)
    try:
        with os.fdopen(fd,'w') as stream:
            stream.write(text); stream.flush(); os.fsync(stream.fileno())
        os.chmod(name,mode); os.replace(name,path)
    finally:
        Path(name).unlink(missing_ok=True)

def prepare():
    if STATE.exists(): raise RuntimeError('Existing cold probe state; inspect it before preparing again')
    if CONFIG.is_symlink(): raise RuntimeError('monitors.lua is a symlink')
    original=CONFIG.read_text()
    if BEGIN in original or END in original: raise RuntimeError('Existing markers')
    if command('hyprctl','configerrors'): raise RuntimeError('Existing Hyprland config errors')
    STATE.mkdir(parents=True,mode=0o700)
    (STATE/'monitors.lua.original').write_text(original)
    # Serialized fixed path, not device text. HOME control chars are refused.
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+',str(STATE)): raise RuntimeError('Unsupported state path')
    log=json.dumps(str(STATE/'cold-start.log'))
    block='''
-- >>> station-m0-cold (observation only) >>>
do
  local function collect(get)
    local up = {}
    if type(get) == "function" then
      local ok, list = pcall(get)
      if ok and type(list) == "table" then
        for _, m in ipairs(list) do
          local ok2, name = pcall(function() return m.name end)
          if ok2 and type(name) == "string" then up[name] = true end
        end
      end
    end
    return up
  end
  -- Exercises the guard's failure cases without changing compositor APIs.
  local safe = next(collect(nil)) == nil
    and next(collect(function() error("m0 simulated failure") end)) == nil
    and next(collect(function() return {} end)) == nil
    and next(collect(function() return nil end)) == nil
  local up = collect(hl.get_monitors)
  local names = {}
  for name in pairs(up) do
    if name:match("^[A-Za-z0-9_.:-]+$") then table.insert(names, name) end
  end
  table.sort(names)
  -- Observation only: no hl.monitor, disable, mirror or dispatch calls.
  pcall(function()
    local proc = io.open("/proc/self/stat", "r")
    local pid = proc and proc:read("*l"):match("^(%d+)") or "unknown"
    if proc then proc:close() end
    local out = io.open(LOG_PATH, "a")
    if out then
      out:write(tostring(os.time()), "\\tpid=", pid, "\\tgetter=", type(hl.get_monitors),
        "\\tcount=", tostring(#names), "\\tguardSafe=", tostring(safe),
        "\\tup=", table.concat(names, ","), "\\n")
      out:close()
    end
  end)
end
-- <<< station-m0-cold <<<
'''.replace('LOG_PATH', log)
    (STATE/'block.lua').write_text(block)
    try:
        atomic(CONFIG,original.rstrip()+'\n'+block)
        command('hyprctl','reload')
        errors=command('hyprctl','configerrors')
        if errors: raise RuntimeError(errors)
        time.sleep(.3)
        lines=(STATE/'cold-start.log').read_text().splitlines()
        if not lines or not all('guardSafe=true' in line for line in lines):
            raise RuntimeError('Guard probe did not log a safe warm evaluation')
        print('Prepared observation-only cold probe. Warm result: '+lines[-1])
    except Exception:
        atomic(CONFIG,original); command('hyprctl','reload'); raise

def capture(label):
    if label not in ['connected','laptop-only']: raise RuntimeError('Use connected or laptop-only')
    data={'label':label,'capturedAt':time.time(),
          'compositorSignature':os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'),
          'evaluations':(STATE/'cold-start.log').read_text().splitlines(),
          'configErrors':command('hyprctl','configerrors'),
          'monitors':[{k:m[k] for k in ['name','width','height','x','y','scale','disabled','mirrorOf']}
                      for m in json.loads(command('hyprctl','monitors','all','-j'))]}
    atomic(STATE/(label+'.json'),json.dumps(data,indent=2)+'\n')
    print(json.dumps(data,indent=2))

def finish():
    text=CONFIG.read_text()
    if text.count(BEGIN)!=1 or text.count(END)!=1: raise RuntimeError('Missing/duplicate probe markers')
    start=text.index(BEGIN); end=text.index(END)+len(END)
    if end<start: raise RuntimeError('Reversed probe markers')
    # Remove only our block, preserving edits made since preparation.
    atomic(CONFIG,text[:start]+text[end:].lstrip('\n'))
    command('hyprctl','reload')
    errors=command('hyprctl','configerrors')
    if errors: raise RuntimeError(errors)
    print('Cold probe removed; captured results remain at '+str(STATE))

if __name__=='__main__':
    action=sys.argv[1]
    if action=='prepare': prepare()
    elif action=='capture': capture(sys.argv[2])
    elif action=='finish': finish()
    else: raise SystemExit('Usage: cold-login.py prepare | capture connected|laptop-only | finish')
