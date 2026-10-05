# M0 cold-login check

Status: **completed.** The observation-only block has been removed from
`~/.config/hypr/monitors.lua`. Captures and the original-file backup remain
under `~/.local/state/omarchy/station-m0-cold/`.

The probe called guarded `hl.get_monitors()`, recorded connector names and
count, and emitted no monitor rules, disable, mirror, bind or dispatch calls.
Both cold evaluations returned an empty table even though the connected login
later exposed two monitors and the laptop-only login exposed one. This is the
M0 architecture result recorded in `SPEC.md` and `M0.md`.

## Pass 1: external display connected

1. Leave `HDMI-A-2` connected and powered on.
2. Save work and log out of the Hyprland session completely. Locking the screen
   or restarting the shell is not a cold compositor start.
3. Log back in and wait until the bar and both displays have settled.
4. Open a terminal in this repository and run:

   ```sh
   python3 tools/v2/cold-login.py capture connected
   ```

5. Confirm that both displays look and behave normally.

## Pass 2: laptop display only

1. Save work and log out again.
2. Disconnect `HDMI-A-2` while logged out.
3. Log back in on the laptop panel and wait until the bar has settled.
4. In this repository, run:

   ```sh
   python3 tools/v2/cold-login.py capture laptop-only
   ```

5. Confirm that the laptop display looks and behaves normally.

After both captures, reconnect the external display if desired and tell Codex
the captures are complete. Codex will review the compositor PID, getter type,
monitor count, guard result and current monitor snapshot, record the outcome,
then remove the probe with:

```sh
python3 tools/v2/cold-login.py finish
```

If the desktop does not start normally, switch to a TTY with
`Ctrl+Alt+F3`, log in, change to this repository, and run the same `finish`
command. Then return with `Ctrl+Alt+F2` or reboot. The command removes only the
uniquely marked observation block and reloads Hyprland; it preserves unrelated
edits made after preparation.
