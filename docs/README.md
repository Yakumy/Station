<!-- summary: How this documentation is laid out, the index of documents, the glossary, how to keep the pages correct. -->
# Station documentation

This folder is the single documentation set for Station. There is one current
document per topic, and no document describes an older version. Git history keeps
older specifications and evidence ([where to find them](decisions.md#historical-records)).

Users start with the [README](../README.md). Coding agents start with
[AGENTS.md](../AGENTS.md).

## Find one section

`python3 docs/find.py` finds and prints single sections, so neither a person nor an agent
has to read a whole document:

```sh
python3 docs/find.py                           # every document, with its size
python3 docs/find.py screen recording crash    # ranked sections for some words
python3 docs/find.py lib/color/ColorMatch.js   # what documents a source file
python3 docs/find.py contracts/bars            # the outline of one document
python3 docs/find.py contracts/bars#controls   # print one section
```

## Documents

[Contracts](contracts.md), [Platform findings](platform-findings.md) and the
[Design system](design-system.md) each index a folder of topic pages: `contracts/`,
`platform/` and `design/`.

<!-- index -->
| Read | For | Tokens |
| --- | --- | --- |
| [Architecture](architecture.md) | How the code fits together: folders, owners, panel lifetime, bridge, files on disk, how to add a feature. | 2900 |
| [Station branding palette](branding.md) | Colors, themes and media rules for videos, banners, screenshots and GIFs. Not for runtime UI. | 1400 |
| [Contracts](contracts.md) | What Station must and must never do: scope, principles, who owns which setting, security. Index of the per-feature contracts. | 2000 |
| [Decisions](decisions.md) | Why design choices were made, where historical records are, open questions. | 2800 |
| [Design system](design-system.md) | The UI rules: no private palette, actions and choices, corners, elevation, spacing, do-not list, acceptance. Index of the design pages. | 2900 |
| [Qualify a change on real hardware](hardware-testing.md) | Prepare, capture, cases to run, restore, operator results. Asks the user first. | 1400 |
| [Omarchy's bar and Station's bar](omarchy-bar.md) | How Station's bar is compared with Omarchy's, how to close a gap, what Station adds, its own widgets. | 1600 |
| [Platform findings](platform-findings.md) | How Hyprland, Omarchy and Quickshell behave: evidence tags, tested versions, known traps, what was never tested. Index of the per-topic findings. | 2900 |
| [Releasing](releasing.md) | Update the installed plugin, publish dev and main, submit to the marketplace. | 1100 |
| [Testing](testing.md) | Run the checks, test layout, QML harnesses, CI, evidence tags, coverage gaps. | 1900 |
| [Widgets that need their own service](widget-services.md) | For plugin authors: how a widget reaches its own service on a replacement bar. | 900 |
<!-- /index -->

## Glossary

Station keeps these terms distinct. Mixing them causes bugs.

| Term | Meaning |
| --- | --- |
| **Station** | One workspace on each active output. Switching a station switches every output together. |
| **Output** | A monitor as Hyprland reports it. |
| **Connector** | An output's `name` from `hyprctl`, for example `HDMI-A-2`. Validated before any use. |
| **Identity** | A physical monitor's stable key, derived from its description. Untrusted text, used only for matching. |
| **Lane** | A persistent preference, 1 to 3, that orders an output among the others. |
| **Slot** | An output's current position in the committed map. Slots are always dense. |
| **Role** | The label the panel shows, derived from lane order. Never stored. |
| **Map** | The committed ordered list of independent outputs, saved in `workspace-map.json`. |
| **Journal** | The pending migration saved in `workspace-map.json` before any window moves. |
| **Baseline** | The original station and output of each window, kept until Keep succeeds. |
| **Preview** | A temporary topology change that waits for Keep or Revert. |
| **Evacuation** | The hand-off that closes an open panel before its output changes. |
| **Lease** | Station's record that it hid a stock Omarchy widget, and where that widget sat. |
| **Owner** | The one module that holds a protocol's state. See [Architecture](architecture.md). |
| **Port** | A narrow callback or data input that an owner receives instead of the Service object. |
| **Direct path / bridge path** | How the panel reaches the service: live object under the stock bar, detached snapshots under a replacement bar. |

## Keep the documents correct

Change the documents in the same commit as the behavior. A claim about behavior belongs
in `contracts/`, and a claim about an external system belongs in `platform/` with its
evidence tag. If code and a document disagree, find out which one is wrong and fix it.
Do not silently pick one.

`python3 docs/find.py --check` runs with the other checks and fails when:

- a document is over 12,500 bytes or a section is over 5,000. Add a heading or split it
  by topic, and never shorten evidence to fit. The changelog is exempt;
- a link or an anchor is broken;
- a source file is covered by no document;
- an index table is stale. `python3 docs/find.py --index` rewrites them.

A new document starts with two comments. `summary` is what search and the indexes show,
so name the subjects in it. `code` lists the source files it covers:

```md
<!-- summary: Gaps, Dwindle split, rounding and animation speed. -->
<!-- code: lib/windows/** -->
```

Give each subject its own heading with the words a reader would search for. Extend the
section that already covers a subject before you add a dated one.
