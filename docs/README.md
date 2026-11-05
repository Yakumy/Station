# Station documentation

This folder is the single documentation set for Station. There is one current
document per topic, and no document describes an older version. Git history keeps
older specifications and evidence ([where to find them](decisions.md#historical-records)).

Users start with the [README](../README.md). Coding agents start with
[AGENTS.md](../AGENTS.md).

## Find the right document

| You want to | Read |
| --- | --- |
| Understand how the code fits together, or find a feature's owner | [Architecture](architecture.md) |
| Learn what Station must do, and what it must never do | [Contracts](contracts.md) |
| Run checks, add a test, or qualify a change on real hardware | [Testing](testing.md) |
| Install an update on this machine, publish, or submit to the marketplace | [Releasing](releasing.md) |
| Learn how Hyprland, Omarchy and Quickshell actually behave | [Platform findings](platform-findings.md) |
| Build or change panel UI | [Design system](design-system.md) |
| Create a video, banner, screenshot or theme | [Branding](branding.md) |
| Learn why a design choice exists, or see what is still undecided | [Decisions](decisions.md) |

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

Change the documents in the same commit as the behavior. A claim about behavior
belongs in [Contracts](contracts.md), and a claim about an external system belongs
in [Platform findings](platform-findings.md) with its evidence tag. If code and a
document disagree, find out which one is wrong and fix it. Do not silently pick one.
