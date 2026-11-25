<!-- summary: Layer-rule blur with global blur off, pass count, measured thickness against the stock bar. -->
<!-- code: lib/bars/BarLayer* -->
# Bar blur and thickness

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Thickness and layer blur

| Fact | Tag |
|---|---|
| A live stock-versus-Station screenshot check under the active theme and scale measured the same reserved thickness: 26 logical pixels for top/bottom bars and 28 logical pixels for left/right bars. The menu/icon painted bounds were centered alike. Station should continue using `Style.bar.sizeHorizontal` and `Style.bar.sizeVertical`; a custom thickness would not repair the reported optical imbalance. | [LIVE] |
| Hyprland 0.56.2 on this machine reports `decoration:blur:enabled = false`. A reversible live `hyprctl eval` probe successfully created a named `hl.layer_rule` matching `omarchy-bar` with `blur = true` and `ignore_alpha = 0.1`, enabled global blur through `hl.config`, verified the option became true, then disabled the rule and restored the option to false. This supports a leased runtime implementation; it does not justify leaving global blur enabled when no Station bar requests it. | [LIVE][SRC] |
| First live acceptance of the Background commit found Blur dark and visibly blocky. At that point Hyprland reported size 8 and only 1 pass; the bar also painted a 72%-opaque theme background over the result. The follow-up keeps size 8, leases 3 passes as recommended for smoother Kawase blur, and replaces the visible tint with a 1%-alpha activation mask. The lease now records and restores enabled, size, and passes. | [LIVE][SRC] |

## Bar Blur with global blur off (2026-11-05)

- [LIVE] The `station-bar-blur` layer rule existed and was enabled, and the bar was not
  blurred, because `decoration:blur:enabled` is false on default Omarchy. Enabling only that
  option at runtime frosted the pills immediately.
- [LIVE] At Hyprland's default single pass, a magnified capture shows a blocky lattice. Three
  passes are smooth, matching the earlier finding on this bar.
- [INFERRED] `hl.window_rule` accepted `no_blur` on a probe rule with no configuration
  error. Whether it reaches already open see-through windows was not measured.
