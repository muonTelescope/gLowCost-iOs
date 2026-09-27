# Design system: violet & phosphor

One dark look for the app, the Live Activity, the Dynamic Island and the widgets. All tokens live in three files in `MuonMonitor/Shared/`. The app and the widget extension both compile them, so a change in one place updates every surface.

| File | Contents |
|---|---|
| `Palette.swift` | Colours, pair line colours, the green map ramp, `Phase` tints |
| `Typography.swift` | Raleway and IBM Plex Mono styles, navigation bar fonts, `.capsLabel()` |
| `Chamfer.swift` | `ChamferedShape`, the card/panel modifier, frosted glass, button styles |
| `Glyphs.swift` | `ChannelLabel` (CH⁰₁ notation), `MuonGlyph`/`MuonMark`, `PairLines` |
| `MinuteBars.swift` | Minute bar chart built from shapes, so it also renders in widgets |

## Colour

| Token | Hex | Job |
|---|---|---|
| `ground` | `#120E1A` | App background, widget and Live Activity background |
| `panel` → `panelSheen` | `#1C1628`, sheen `#231C33` | Cards, with a faint lighter top |
| `raised` | `#261E35` | Controls, selected segments, tiles inside cards |
| `hairline` | `#3A2F4F` | 1 px edges, dividers |
| `brightEdge` | `#5E4A93` | Hero card, selected tab or segment, the card that matters most on a screen |
| `ink` / `muted` | `#EEE9F5` / `#A89CBF` | Text |
| `violet` | `#9B7BFF` | Structure, pressure, toggles, Control Center tint |
| `lilac` | `#C9B6FF` | Muon tracks, icons, setup state |
| `phosphor` | `#5BE3A0` | Data: counts, minute bars, rate lines, physics state, temperature, map ramp |
| `pink` (`alert`) | `#FF8FB1` | **Only** alerts and destructive actions: overdue, Turn HV off, Reload FPGA, Forget MuonP4 |
| Primary button | `#AE93FF` → `#8462F0`, edge `#C9B6FF`, text `#16101F` | `.muonPrimary` |

The older semantic names (`accent`, `card`, `secondaryText`, `warning`…) still exist and map onto these tokens, so older call sites keep compiling. New code should use the token names.

## Type

- **Raleway** (bundled variable font `Raleway[wght].ttf`, unmodified): titles 800, headings 700, subheads 600, body 500. `Typography.raleway(size, weight, relativeTo:)` sets the `wght` axis and turns on lining figures, so digits inside Raleway text sit on the baseline.
- **IBM Plex Mono** 400/500/600: every number that updates (counts, rates, pressure, temperature), units, and the tracked caps labels (`.capsLabel()`).
- Everything scales with Dynamic Type relative to a system text style. The Live Activity and Island use `Typography.monoFixed` so their layout stays stable.
- If a font file fails to load, Raleway falls back to the system font and Plex Mono to the system's default.

## Cuts instead of rounded corners

`ChamferedShape` is an `InsettableShape` with an independent cut per corner, so the same shape clips the fill **and** strokes the hairline (`strokeBorder`), and the edge follows the diagonals exactly.

| Use | Cut |
|---|---|
| Cards and panels (`.card()`, `.panel()`) | Top-right and bottom-left, 14 pt (hero 18 pt) |
| Buttons (`.muonPrimary`, `.muonSecondary`, `.muonDestructive`) | All four corners, 10 pt (9 pt secondary) |
| Icon buttons, segments | All four, 6 pt |
| Chips (phase, tags, demo) | All four, 4 pt |
| Floating tab bar / logging bar | All four, 12 / 10 pt |

System-owned outlines keep Apple's shapes: Dynamic Island, Live Activity container, widget and Control Center outlines, circular Lock Screen widgets.

## Surfaces

- Cards are **solid** (no blur) with a subtle sheen gradient, so numbers stay crisp.
- **Frosted glass** (`.chamferGlass()`) only on floating elements: the custom tab bar, the logging bar and the chart readout. Sheets use the system presentation.
- Gradients only where they carry meaning: hero fade behind the count, panel sheen, primary button.

## Channel notation

`ChannelLabel(channel:)` draws CH with the first paddle as a superscript and the second as a subscript: CH⁰₁, CH⁰₂, CH¹₂ (and CH⁰₁₂ for the triple). The sum of the three pairs is **ΣCH**. The digits never drop below 11 pt (review fix 2). VoiceOver reads "channel 0 1". `ChannelLabel.plain(_:)` gives a Unicode version for plain strings (share text, compare rows).

## Glyph

`MuonGlyph` is a SwiftUI `Shape` (two tracks crossing a paddle) used instead of the generic `line.diagonal` symbol in the Dynamic Island, Live Activity, widgets and the Now explainer. A Shape renders everywhere a symbol does, with no asset catalog needed.

## Charts

- Minute bars: phosphor everywhere, grey dash for a missed minute.
- Rate line: phosphor with a ±1σ band; event markers are dashed muted rules.
- Live Activity: three pair lines (`PairLines`, phosphor, mint `#A6F5CF`, lilac) when the app sends `recentPairs`; otherwise green minute bars.
- Map: rate-coloured track on the green ramp, lilac-edged marker.

## Motion

The Now hero's muon tracks drift gently (a `TimelineView` at 15 fps in `TrackPlate`). With **Reduce Motion** on they are drawn still, and the Pair radar stops pulsing.

## Switches

- `useSystemTabBar` (`@AppStorage`, Settings › Debug in Debug builds, or `defaults write <bundle id> useSystemTabBar -bool YES`): use Apple's Liquid Glass tab bar and `tabViewBottomAccessory` logging bar instead of the custom chamfered bars.
- Dark only: `.preferredColorScheme(.dark)` on the root and `UIUserInterfaceStyle = Dark` in `Info.plist`.
