# Station v2 test results

Validated on 2026-10-05 with Omarchy 4 and Hyprland 0.56.x.

## Automated

- Model tests cover all seven non-empty present sets, convergence, station
  preservation, lane stability and reuse, fourth-display exclusion, role
  swaps, LTR/RTL navigation, managed-only station existence, logical geometry,
  overlap detection, and exact mode selection.
- Binding tests cover menu, `hyprctl`, and Lua conflict sources, modifier
  normalization, approved replacements, stale Station bind removal, custom
  actions, and unknown-source behavior.
- Monitor generator tests cover connector and exact-mode rejection, guarded
  disables, explicit mirror clearing, marker uniqueness, EOF placement,
  malformed marker refusal, plain geometry, and external-rule warnings.
- Recovery tests execute the detached cleanup template against a fixture and
  verify literal marker replacement and lease clearing. Static checks cover
  watchdog and Keep rollback requirements.
- Theme-token scanning reports zero literal palette values across all runtime
  QML, JS, and manifest sources. The Omarchy manifest validator passes.
- Both QML entry points compile against the installed `qs.Ui` and `qs.Commons`
  components.

## Live integration

- Service-owned IPC worked while the panel was closed.
- The Display-style panel rendered anchored below the Station bar widget with
  keyboard focus and outside/Esc dismissal.
- Station installed exactly 36 bindings. A shell restart kept the count at 36.
- Twenty physical `CTRL+SUPER+Left/Right` samples measured p50 66 ms and p95
  68 ms (range 64–69 ms).
- A no-change two-display preview created its watchdog token; Keep wrote a
  guarded block plus its plain copy, removed the token, reloaded cleanly, and
  preserved exact mode strings.
- Normal removal restored `omarchy.workspaces` to `left[1]`, restored the
  default `SUPER+1` binding, removed all Station bindings, cleared the persisted
  lease, replaced the managed block body with plain geometry, and left
  `hyprctl configerrors` empty.
- A shell `SIGKILL` during the M0 preview was recovered by the detached
  watchdog after about 20 seconds.
- Two cold compositor starts, one with HDMI and one laptop-only, returned an
  empty monitor list during `monitors.lua` evaluation and later discovered the
  expected displays without configuration errors. The guarded block and
  runtime service path reflect that result.

The fourth-independent-monitor case remains hardware-unavailable and is
documented as such in the accepted M0 gate. Physical unplug/replug and role
swap scenarios remain release-candidate manual tests because they move live
windows or require hardware interaction.
