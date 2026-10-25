# Station branding palette

Approved on 2026-10-25. Use this reference for new Station videos, banners,
`preview.png`, screenshots, GIFs, and the Station desktop theme.

The background colors below were supplied and approved by the project owner
from the existing preview/banner artwork. This is the agreed branding palette,
not a claim that every historical asset uses these exact values. It supersedes
the darker `#161B1F` background used in the earlier launch-video palette for
future branded media. Existing media has not yet been regenerated.

## Core colors and roles

| Role | Hex | Usage |
| --- | --- | --- |
| Deep background | `#20262A` | Darkest surface; supporting shade added to the artwork palette |
| Dark background | `#272E33` | Secondary dark surface; artwork anchor |
| Main background | `#283035` | Default background and terminal BG; artwork anchor |
| Lighter background | `#2C3433` | Subtly raised surface; artwork anchor |
| Inactive border | `#49545A` | Quiet separators and inactive outlines |
| Muted text | `#89948A` | Secondary information |
| Main text | `#ECF0E2` | Primary readable text |
| Station olive | `#A6B465` | Logo, brand details, supporting green/success color |
| Station orange | `#EE5F06` | Primary UI accent, active-window borders, focus, cursor, selection background |
| Selection text | `#20262A` | Dark text on orange selection backgrounds |

Orange is the interaction accent. Keep the Station logo olive; do not substitute
olive for orange on active controls or replace the exact orange with a muted
approximation. Use charcoal for most of the composition, warm white for text,
and accents sparingly.

## Aether semantic colors

These are the agreed values for the editor's semantic groups, in display order.
The supporting shades extend the brand anchors; they are not all sampled from
the original artwork.

| Group | Field | Hex |
| --- | --- | --- |
| Background | Darker | `#20262A` |
| Background | Dark | `#272E33` |
| Background | Base | `#283035` |
| Background | Lighter | `#2C3433` |
| Foreground | Muted | `#89948A` |
| Foreground | Dark | `#BCC4B4` |
| Foreground | Base | `#ECF0E2` |
| Foreground | Light | `#F1F4E9` |
| Foreground | Bright | `#F6F7EE` |
| Accent | Orange | `#EE5F06` |
| Accent | Brown | `#995B36` |
| UI | Accent | `#EE5F06` |
| UI | Cursor | `#EE5F06` |
| UI | Sel FG | `#20262A` |
| UI | Sel BG | `#EE5F06` |

## Aether 16-color terminal palette

BG, foreground neutrals, and olive follow the brand palette. The remaining
terminal hues are muted supporting colors for syntax and status distinctions.
Orange is assigned through the semantic roles above; ANSI has no dedicated
orange slot.

| Index | Tile | Hex | Index | Tile | Hex |
| --- | --- | --- | --- | --- | --- |
| 0 | BG | `#283035` | 8 | DIM | `#89948A` |
| 1 | RD | `#CD7770` | 9 | RD+ | `#E9948B` |
| 2 | GR | `#A6B465` | 10 | GR+ | `#BFCC82` |
| 3 | YL | `#C8AF71` | 11 | YL+ | `#E0C58D` |
| 4 | BL | `#829CAA` | 12 | BL+ | `#A0BAC8` |
| 5 | MG | `#B28FA0` | 13 | MG+ | `#CDAABD` |
| 6 | CY | `#85AAA5` | 14 | CY+ | `#A1C7BF` |
| 7 | FG | `#ECF0E2` | 15 | FG+ | `#F6F7EE` |

## Producing consistent media

- Read this palette before creating or regenerating a video, banner, preview,
  screenshot, or GIF. Use these values in new artwork and animation palettes.
- For desktop captures, select the Station theme and keep font size, UI scale,
  and the default wallpaper consistent across the recording set. Show other
  wallpapers deliberately when demonstrating wallpaper features.
- Keep the palette fixed when switching wallpapers; do not re-extract a new
  palette from each photograph. Save the agreed palette as the Station preset.
- Favor wide, quiet landscapes with charcoal shadows, muted olive vegetation,
  and warm orange light. Five candidate directions are dusk dunes, olive hills,
  basalt coast, a mountain sunset, and a desert night sky. These are art direction,
  not an already selected or licensed wallpaper collection.
- For three horizontal 3840 × 2160 displays at native resolution, the combined
  image is 11520 × 2160. Prefer originals 12000–16000 pixels wide and at least
  3000 pixels high for cropping room. Other monitor arrangements need their own
  combined dimensions; an 8K-wide image does not cover this horizontal layout
  at native resolution.
- Before bundling a photograph, verify its original dimensions and redistribution
  license. Record the photographer, source URL, license, and edits, and provide
  attribution wherever its license requires it.

## Relationship to the plugin design system

This document governs branding assets and the optional Station desktop theme.
The running plugin still uses Omarchy's `qs.Commons` color tokens and follows
the user's selected theme, as required by the [design system](v2/DESIGN-SYSTEM.md).
Do not hardcode this branding palette into plugin QML. Apply the Station desktop
theme to obtain these colors for recordings through the normal theme tokens.
