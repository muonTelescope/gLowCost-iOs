# Mockup review: the seven fixes

Claude reviewed the rendered violet & phosphor mockup on 2026-09-26 (about 11 PM ET). Its review is archived verbatim below, followed by how each fix is handled in the Swift code. The renders in this folder were made **before** these fixes, with fallback fonts.

## Review (verbatim)

> I rendered all 12 screens and the cut-corner borders now work: every card, button, chip and the tab bar has a continuous hairline that follows the diagonals. The canvas itself needs a sign-in, so I rendered the design files directly. Raleway and IBM Plex Mono couldn't load in that setup, so letter shapes and text widths may differ slightly; layout, colours and corners are accurate.
>
> **Working well**
> - The frosted tab bar and logging bar read well, and the selected tab's brighter violet edge makes the current tab clear.
> - The primary buttons (Start physics run, Export CSV and JSONL, Connect and pair, Apply) have the right weight.
> - Green for data works across Now and Run detail: bars, rate lines, sparklines and the GPS track.
> - The Dynamic Island, widget and Control Center shapes sit comfortably next to the chamfered app screens.
>
> **Fixes I'd make**
> 1. **Now hero:** the muon lines run straight through the "COINCIDENCES, LAST MINUTE" label, because the fade starts below it. The fade should start higher, or the label should sit on a solid strip.
> 2. **Channel labels are too small at caption sizes.** CH with superscript and subscript reads well at 15 px and up (the chart channel picker, the counting-statistics tiles). In the pair tiles, the session totals line, the expert counter table, the Lock Screen and the Island, the two digits come out about 7 px and are hard to read. I'd make those labels at least 14–15 px, or use a slightly larger digit size.
> 3. **Pink means two things.** It marks alerts and destructive actions (overdue, Turn HV off, Forget MuonP4), but it's also on the Power bank tag, the "Illustrative" label and the Mains warning chip. I'd keep pink for alerts and destructive actions only and give tags violet, green or neutral chips.
> 4. **Data colour is inconsistent.** Minute bars are green in the app but violet on the Lock Screen Live Activity and the medium widget. They should be green everywhere.
> 5. **Run detail rate chart:** the tooltip sits on top of the peak it describes. It should go above the plot or on the opposite side of the marker.
> 6. **Line wrapping:**
>    - Pressure card caption: the P₀ value wraps onto a second line.
>    - Mains run warning chip in Runs: two lines, cramped.
>    - Now screen stat labels ("coincidences", "exposure"): tight at this width.
> 7. **Frame heights:** Detector and Settings have large empty areas below the content. I'd trim them.
>
> Want me to apply all seven fixes to the mockup?

## How the app implements each fix

| # | Fix | Where in the code |
|---|---|---|
| 1 | Hero fade starts above the "COINCIDENCES, LAST MINUTE" label | `App/Views/NowView.swift` hero: the gradient over `TrackPlate` fades from 18% to 42% of the height and is solid from 50%, so the label and count sit on a solid ground. The Share card uses the same fade. |
| 2 | Channel digits legible at small sizes | `Shared/Glyphs.swift` `ChannelLabel`: the superscript/subscript digits are 72% of the label size but never below `ChannelLabel.minDigit` (11 pt). Pair tiles, counters and the Live Activity legend use labels of 14 pt or more. |
| 3 | Pink only for alerts and destructive actions | `Shared/Palette.swift` (`alert`/`pink`), `App/Model/Tags.swift` (tag groups are violet, lilac, green or neutral), `DemoBanner` is violet, the Runs health note is lilac. Pink remains for overdue, Turn HV off, Reload FPGA, Forget MuonP4 and the expert warning. |
| 4 | Green minute bars everywhere | `Shared/MinuteBars.swift` defaults to `Palette.data` (phosphor); the Live Activity fallback bars and the small/medium widgets pass it explicitly. |
| 5 | Tooltip away from the peak | `App/Views/RunDetailView.swift` `RateChart`: the readout is a glass chip in a strip **above** the plot, aligned to the opposite half from the selected bin. |
| 6 | No bad wrapping | `lineLimit(1)` + `minimumScaleFactor` on the pressure/temperature range caption, stat tiles, tab labels and pair totals (`ViewThatFits` on Now); the Runs health note is a one-line chip; long explanatory text uses `fixedSize(horizontal: false, vertical: true)` so it wraps cleanly instead of truncating. |
| 7 | Less empty space on Detector and Settings | Both screens end 8 pt after the last card; the floating bars reserve their own inset (`FloatingBars.reservedHeight`) instead of each screen padding the bottom. |
