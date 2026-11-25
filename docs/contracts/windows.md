<!-- summary: Gaps, Dwindle split, rounding and animation speed: ranges, the save and apply sequence, the preview. -->
<!-- code: lib/windows/** -->
# Windows tab

The Windows layout preview omits bar indicators and reserves no space for them.
Simulated windows fill each monitor inside the chosen outer gap on all four edges.
This preview does not change the compositor's actual bar-aware work area.

The controls change **global compositor settings**: inner gap, outer gap, Dwindle split,
rounding and animation speed.

| Control | Range | Notes |
| --- | --- | --- |
| Inner gap | 0 to 160 | The full visible gap. Hyprland's `gaps_in` is half of it. |
| Outer gap | 0 to 160 | Never moves the bar. Solid and Blur default bars keep it beside the bar. A Transparent default bar gets no gap on its edge. A Pill bar ignores it: windows sit `Style.space(8)` from the pill in every background, the same safe space the pill keeps from the monitor. |
| Next-window split | 25 to 75% | Dwindle only |
| Rounding | 0 to 20 | Follows `decoration:rounding`, which Omarchy also uses for shell corners |
| Animation speed | 0, 0.25, 0.5, 0.75, 1, 1.24, 1.5, 1.75, 2 | 0 disables animations. Window duration is 400 ms divided by speed. |

Sliders preview while dragging and apply on release:

1. Suspend autoreload.
2. Save only that control's entry in the marked section at the beginning of
   `looknfeel.lua`.
3. Compile the candidate for syntax, without executing personal Lua.
4. Apply only that setting through `hyprctl eval`.
5. Restore autoreload on every exit, then read back the applied value.

The bar edge is handled by runtime `hl.workspace_rule` entries named `m[<connector>]`
with a directional `gaps_out` table, written by `BarLayerSync.syncBarGaps` (policy in
`Windows.gaps`). They are never saved. Station sends them after a reload, a bar
setting change, a display change and a read-back of the outer gap. A monitor that
once had a rule keeps getting one, so leaving Transparent restores the full gap.

Success causes **no full reload and no fixed sleep**. A failed apply conditionally
restores the file and reloads. Personal settings later in Lua order win on the next
reload, and Station shows that result without retrying.

The slider keeps its selection during input and through read-back. Unrelated updates
must not reset an active edit. Controls stay busy until read-back ends, including a
failed read. Proxy actions refresh the busy snapshot before the host slider completes
release.

The panel shows global defaults. It does not inspect per-window rules. External values
display unrounded until the user edits that control.

The preview shows two windows per monitor at real proportions, without monitor
names. After a speed change, WINDOW tiles move through every enabled monitor
in order, one transfer at a time, while NEXT WINDOW tiles stay and reflow. With one
enabled monitor, the two tiles exchange sides, pause, then exchange again so WINDOW
finishes on the left and NEXT WINDOW on the right. Disabled monitors stay still.
Repeated changes queue the latest speed without interrupting a move. This never
moves a real window.
