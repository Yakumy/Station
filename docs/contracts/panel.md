<!-- summary: Frame size, styles, tabs, keys, the Workspaces tab, dropdown scroll hints, text size, brightness, reopening after a bar rebuild. -->
<!-- code: lib/panel/** Panel.qml -->
# Panel

The panel is a bar-widget popout. The Displays-style popout replaces the on-demand panel
kind, which does not inject the `anchorItem` and `bar` that `KeyboardPanel` requires.

## Frame and tabs

- The frame requests `Style.space(996)` by `Style.space(620)`, capped by the host. Tabs
  do not change it. The header and tabs stay fixed, and the body scrolls vertically only
  on overflow, returning to the top on a tab change.
- All six layout canvases center a plain-text monitor name inside each monitor.
  Displays separates the name from its role dropdown with `|`; Workspaces shows
  the same separator and role as read-only text. Other controls and status text stay
  clear of the name, including the Windows animation.
- Feature control frames use their pre-`ea956ed` width, capped to their column.
  Sliders, dropdowns and row buttons use 99% of the width within the row padding,
  centered. Slider knobs, including their hover enlargement, remain inside the
  frame at both endpoints.
  Action buttons also use 99% of their previous width.
- Displays keeps its Mode menu inside the layout canvas at the top right. It uses
  the same preview and panel-evacuation path as the former toolbar menu.
- The tabs are Displays, Workspaces, Bar, Windows, Color Match, Wallpaper, Keybindings and Settings. Service
  setters keep numeric tab indices, and `Tabs.js` names them for feature code.
- The tabs stay label-only, with no numbered keycaps or digit shortcuts. While the panel
  has focus, plain `q` or Escape closes it; Shift, Control, Alt and Meta leave the key to
  other actions. Tab and arrow navigation still work.
- Panel style is Bar landscape (at the bar icon, the default), Bar portrait, or Center landscape.
  Bar portrait uses the stock control-panel width (`Style.space(380)`), stacks each layout
  above its controls with equal 370-unit frame heights. The 72-unit gap between visible frames
  includes the control heading. Its hairline divides that gap into equal 36-unit
  halves; the bottom clear space is also 36 units. The card keeps
  one fixed base height across tabs; content scrolls when screen fitting reduces the available height. A rule separates the
  Station header from its wheel-scrollable tab rail; no scrollbar is visible. Its action
  drawer alone adds card height while Keep/Revert or Cancel/Apply is needed. Portrait drawers are 72 scaled units high (the sum of both divider gaps). Buttons are horizontally centered. A message sits under them in caption type, at most two lines, and the buttons and message are vertically centered together. `lib/panel/ActionDrawer.qml` owns every feature drawer and the preview strip, and positions its children with `x`/`y` only: switching anchors at runtime once left Keep unpainted in a live portrait preview. Keybindings rows keep the label on the left and right-align the combo; a conflict is shown in the combo color, the conflict card's choices stack centered, and Cancel/Apply sit centered under the editor. Center landscape
  uses the output's full-screen card and stays clear of the bar on small screens.
- Settings holds the two Show switches, panel style,
  and the installed version. Compact mode and open apps are on the Workspaces tab.
## Workspaces tab

- The Workspaces tab's monitor positions are fixed: no monitor drag and no selection,
  only zoom and pan. Each output centers its name; managed workspaces and count
  controls occupy the upper half.
- Every Workspaces control edits a draft that the layout draws at once. Cancel and Apply
  appear once the draft differs from the saved values. Apply sends the whole draft in one
  `setSetting("workspaces", …)` call; Cancel restores the saved values.
- In Repetitive every monitor has − and + after its badges (1 to 10). In Non-repetitive
  only the last monitor has them: + adds the next number to it, − removes the highest
  number, wherever it is, while its monitor keeps one. Non-repetitive badges drag onto
  another monitor, which then owns that number; each monitor keeps 1 to 10.
- The Workspaces frame keeps five equal-height dropdown rows visible at a time; the
  rest scroll inside the frame, so the portrait panel keeps its bottom padding. Mode,
  Indicator style, Indicator shown, Compact mode, Stations Direction and Show open apps
  share the list. Titles sit at the top left, dropdowns use the shared inset width, and
  hints sit at the bottom left. A dropdown menu whose options overflow carries a thin
  accent-colored thumb inside the popup, and the Workspaces control frame carries the
  same thumb while its rows overflow. Both are the shared `ScrollThumb`: sized from the
  list's visible area, it travels the middle 80% of the list so its rounded ends stay
  inside the container's corners. It shows only while the pointer is on the thumb or
  drags it, through a grab strip wider than the line; hovering the rest of the menu or
  frame shows nothing. Holding the left button on the strip and dragging moves the list
  with the pointer, and the strip takes that press away from the rows under it. Once
  per shell session, the first overflowing dropdown menu to open and the Workspaces
  control rows the first time they appear scroll a little and back, with the thumb
  shown, so the user sees that they scroll. Dropdown menus share one hint; the session
  record lives in `ScrollHint.js`, imported only by `ScrollThumb.qml`, and persists
  nothing. The hint waits 300 ms for the popup or tab to arrive, starts from where the
  list rests (upward when it already rests at the end), stops when the user drags or
  grabs, and is skipped under reduced motion without using up its key. Page lists keep
  their silent scrolling. Mode defaults to Station; Compact mode
  defaults to On hover. Direction moves from Displays to this draft and retains LTR,
  RTL, TTB and BTT; it is disabled outside Station mode with "only work with Station mode". Indicator
  shown offers 1 to 10, defaults to 3, and applies in every mode. Show open apps offers
  Off and On and is disabled with Compact mode On, retaining its saved preference. Mode
  retains the single-output restriction and the Non-repetitive drag hint.
## Text size and brightness

- Text size offers 9, 10, 11, 12, 13, 14, 16 and 20px. It runs
  `omarchy-display-text-size` and changes shell, GTK and terminal text globally.
  The per-monitor control is Scale.
- Brightness reads and writes carry the selected connector, and a notice belongs to its
  control.

## Surviving a rebuild

A bar rebuild destroys the widget and its popout. The service keeps the intent:

- `panelWanted` is written on every open change, and destruction never writes it. A
  rebuilt widget reads `true` and reopens. A real close writes `false`.
- A rebuilt widget reopens the panel only on its own output: the screen it kept while
  open, or its own bar window's screen. Until that window resolves it waits; it never
  takes `panelScreenName` as its own, or it could claim the panel from another output.
- A shell restart starts closed, because the flag is in memory.
- A change that lands before the service binding resolves is held and replayed.
- `closeForPopoutSwitch` is not a dismissal. The bar closes the old copy after the new
  copy opens. The decision waits one event-loop turn, then keeps the flag if any live
  copy shows the panel.
- `rememberedTab` and `rememberedDisplayName` come back too. A real close clears the tab.
