# Design material

| File | What it is |
|---|---|
| [`ios-redesign-plan.md`](ios-redesign-plan.md) | The visual system and product decisions, archived verbatim from the Claude session |
| [`REVIEW-7-FIXES.md`](REVIEW-7-FIXES.md) | Review of the rendered mockup and how each of the seven fixes is implemented |
| [`DESIGN-SYSTEM.md`](DESIGN-SYSTEM.md) | Tokens, type, cuts, glass and charts, mapped to the Swift files |
| `mockup-now.png` | Now: muon-track hero, pair tiles, last hour, pressure and temperature |
| `mockup-run-detail.png` | Run detail: rate chart with readout, pressure and temperature, GPS track, counting statistics |
| `mockup-detector.png` | Detector: connection card, checklist, Start physics run, SD files |
| `mockup-runs-expert-settings-pair.jpg` | Runs list, Expert console, Settings and the pairing screen |
| `mockup-lockscreen-island-widgets-track.png` | Lock Screen Live Activity, Dynamic Island states, widgets, Control Center, GPS track |

The renders come from the HTML mockup and **predate the seven review fixes**. They were drawn with fallback fonts, because Raleway and IBM Plex Mono could not load in the render environment. Colours, layout and cuts are accurate; letter shapes and text widths differ slightly from the app.

The interactive mockup is a Claude artifact: <https://claude.ai/artifact/4QBP3ZZ6sV1XmzQuUTafKz>. It requires signing in to claude.ai with access to it.

## Live Activity mockups (current)

`live-activity/LockScreen.dc.html` and `live-activity/Island.dc.html` are the design-canvas sources for the Lock Screen Live Activity and Dynamic Island, matched to `MuonMonitor/Widget/LiveActivityWidget.swift` as of September 27, 2026: rate with `/min`, a full-height 30-minute pair-line plot with no caption, and one row with the channel counts (colour over/underlined CH) and pressure · temperature. Plot values are placeholders. The PNG mockups above predate this layout.
