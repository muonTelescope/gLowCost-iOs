# gLowCost iOS: MuonP4 monitor

An iPhone app for the **gLOWCOST MuonP4** cosmic-ray muon telescope. It pairs with the detector over Bluetooth, logs every minute of counts with pressure, temperature and GPS, keeps a history of runs, and shows the live rate on the Lock Screen, in the Dynamic Island and in widgets.

<p align="center">
  <img src="design/mockup-now.png" height="420" alt="Now screen">
  <img src="design/mockup-run-detail.png" height="420" alt="Run detail">
  <img src="design/mockup-detector.png" height="420" alt="Detector screen">
</p>
<p align="center">
  <img src="design/mockup-lockscreen-island-widgets-track.png" width="760" alt="Lock Screen Live Activity, Dynamic Island, widgets and Control Center">
</p>

<sub>Design mockups, rendered before the final review fixes and with fallback fonts. See <a href="design/">design/</a>.</sub>

## What gLowCost / MuonP4 is

gLOWCOST is a low-cost muon telescope: plastic scintillator paddles read by SiPMs, coincidence logic in a small FPGA, and an ESP32-P4 board that counts, logs to an SD card and measures temperature and pressure. **MuonP4** is the detector's firmware and Bluetooth name. Every minute it reports the coincidence counts of three paddle pairs (CH⁰₁, CH⁰₂, CH¹₂), the triple, three raw inputs, and the environment. A minute only counts as *physics* when Wi-Fi is off and high voltage has settled.

The firmware lives in its own repository ([ESP32-P4-gLOWCSOT-cubesat](https://github.com/sawaiz/ESP32-P4-gLOWCSOT-cubesat)). This repository is only the iPhone app.

## Features

| Area | What you get |
|---|---|
| **Now** | The last minute drawn as muon tracks, the count in big numbers, the three pairs, the last hour (one green bar per minute, gaps visible), pressure with 3-hour trend, detector temperature, session totals, a counting-statistics check |
| **Runs** | Every logging session saved on the phone. Summary header ("6 runs · 79 h of physics"), tag filters, search, rename, tags, notes, compare two runs, import SD-card CSVs |
| **Run detail** | Rate chart (1/10/30/60-min bins, ±1σ, event markers, scrub readout), pressure, temperature and altitude, GPS track coloured by rate, counting statistics, SD gap fill, CSV export |
| **Detector** | Connection, health checklist, Start physics run, keep Wi-Fi on, clock sync, SD files (downloads import automatically) |
| **Expert console** | HV byte, DAC channels, FPGA reload (bitstream name when reported), raw counters, radio diagnostics (needs firmware), telemetry (Settings › Expert mode) |
| **Saving** | Pick iCloud Drive › `cosmic` once; each run is written to `cosmic/phone/<date_name>/minutes.csv` and `run.json` every 5 minutes |
| **Outside the app** | Live Activity with Stop button and a three-pair line chart, Dynamic Island, Home and Lock Screen widgets, Control Center toggle and Physics-run button, Siri and Shortcuts |
| **Alerts** | Local notifications: updates stopped (after N minutes, you choose), zero coincidences, sudden jump, SD card problem, noisy counting |
| **Demo** | No detector? **Try the demo instead** on the pairing screen, or run the `MuonMonitor Demo` scheme |

Counts are always **raw**. The app applies no pressure or temperature correction: the detector compensates SiPM bias for temperature itself, and pressure and temperature are stored with every minute for later analysis ([why](docs/HISTORY.md)).

No server, no paid Apple Developer membership, no third-party packages.

## Requirements

- A Mac with **Xcode 27** (iOS 26 SDK).
- An iPhone on **iOS 26** or later for Bluetooth. The Simulator runs the demo. Dynamic Island needs an iPhone 14 Pro or newer.
- A **free Apple ID** is enough (Personal Team).
- Optional: Python 3 (preinstalled on macOS) to regenerate the Xcode project.

## Build and run

```sh
git clone https://github.com/muonTelescope/gLowCost-iOs.git
cd gLowCost-iOs
python3 tools/generate_project.py        # optional: the project is committed, this refreshes it
cp MuonMonitor/Config.local.xcconfig.example MuonMonitor/Config.local.xcconfig
open MuonMonitor/MuonMonitor.xcodeproj
```

1. **Set your team and bundle ID.** In `MuonMonitor/Config.local.xcconfig` (git-ignored) set `MUON_TEAM` to your team ID (Xcode › Settings › Accounts › your Apple ID › Personal Team) and `MUON_BUNDLE_ID` to something unique such as `com.yourname.muonp4`. Alternatively pick the team under Signing & Capabilities for both the **MuonMonitor** and **MuonLive** targets.
2. **Try it without hardware:** choose the **MuonMonitor Demo** scheme, an iPhone simulator, and press Run. It starts with two synthetic runs marked "Demo data".
3. **Run on your iPhone:** choose the **MuonMonitor** scheme and your phone. Turn on Developer Mode on the phone (Settings › Privacy & Security) the first time, and trust your certificate under Settings › General › VPN & Device Management.
4. In the app: Settings › Saving › Folder → **iCloud Drive › cosmic**.

**If Xcode cannot register the App Group** (an error mentioning `group.…`), uncomment the three empty App Group lines in `Config.local.xcconfig`. Everything still works except that Home Screen widgets and the Control Center toggle cannot see live data. The Live Activity and Dynamic Island don't need the group.

Free-account limits: reinstall from Xcode every 7 days; at most 3 such apps per device.

After adding or removing Swift files or fonts, run `python3 tools/generate_project.py` again. Don't edit the project file by hand; build settings live in `MuonMonitor/Config.xcconfig`.

## Pair with the detector

1. Power the detector. It advertises as **MuonP4** about every 15 seconds.
2. Open the app › **Find a detector**. When MuonP4 shows up, tap **Connect and pair**. iOS may ask to pair; pairing encrypts detector commands.
3. Allow location so each minute carries its GPS fix (optional, stays on the phone and in your folder).
4. The first minute arrives within about two minutes. For the first 120 s after boot the detector keeps Wi-Fi on for setup; **Detector › Start physics run** skips that wait.

More in the [user guide](docs/USER-GUIDE.md).

## Project structure

```
MuonMonitor/
  App/            the iPhone app
    Core/         pure Swift: minute records, SD parsing, health, binning, CSV (host-tested)
    Model/        SwiftData models, tag catalogue
    Services/     Bluetooth link, app state, location, cosmic folder, alerts, Live Activity, demo data
    Views/        SwiftUI screens
    Intents/      Siri / App Shortcuts
  Shared/         compiled into the app and the widget: design tokens, glyphs, activity state, intents
  Widget/         Live Activity, Dynamic Island, widgets, Control Center (MuonLive extension)
  Resources/Fonts Raleway and IBM Plex Mono (SIL OFL 1.1) with their licences
  Config.xcconfig bundle ID, team, App Group
tools/generate_project.py   regenerates MuonMonitor.xcodeproj and the two schemes
tests/            host tests (C encoder from the firmware + Swift core)
design/           mockups, redesign plan, review, design system
docs/             protocol, user guide, data format, history
```

## Design system

"Violet & phosphor", dark only: violet ground and structure, lilac muon tracks, **phosphor green for anything that is data**, pink only for alerts and destructive actions. Raleway for words, IBM Plex Mono for numbers. Cut (chamfered) corners with a 1 px hairline that follows the cut; frosted glass only on the floating tab and logging bars and the chart readout. All tokens are in `MuonMonitor/Shared/` (`Palette.swift`, `Typography.swift`, `Chamfer.swift`, `Glyphs.swift`). Details: [design/DESIGN-SYSTEM.md](design/DESIGN-SYSTEM.md).

Two switches:

- `useSystemTabBar`: Apple's Liquid Glass tab bar instead of the custom bars (Settings › Debug in Debug builds, or `defaults write <bundle id> useSystemTabBar -bool YES`).
- `ChannelLabel.minDigit`: minimum size of the channel digits.

## Data storage

- On the phone: SwiftData (runs, minutes, events). Demo mode uses a separate in-memory store and never touches your runs.
- In your folder: pick **iCloud Drive › cosmic** once (security-scoped bookmark, no iCloud entitlement needed). Each run goes to `cosmic/phone/<yyyy-MM-dd_HHmm_name>/minutes.csv` (raw counts, pressure, temperature, GPS for every minute) and `run.json` (name, tags, notes, events), every 5 minutes and when logging stops.
- SD-card logs (`muon_….csv`, and `env_….csv` from older firmware) import from Files or from anywhere in the folder. See [docs/DATA-FORMAT.md](docs/DATA-FORMAT.md).

## Testing

```sh
tests/run-host-tests.sh
```

It builds the firmware's C telemetry encoder, writes a reference packet, and decodes it with the app's Swift decoder. Then it tests the pure-Swift core: run-label sanitising (mirrors the firmware), SD parsing for old and new firmware, gap filling, health statistics, binning and CSV export. Needs `cc` and `swiftc` (Xcode command line tools on macOS, or a swift.org toolchain on Linux).

Hardware checklist:

1. Pair and start logging. The first minute appears within about 2 minutes, and the setup countdown shows in the Dynamic Island.
2. Rename the live run to "Test run". The detector's status shows label `Test_run`, and the SD file name ends in `_Test_run.csv`.
3. Lock the phone for 30 minutes. The Live Activity updates each minute.
4. Walk out of range for longer than the "Alert when updates stop" time. The alert arrives, the Island shows overdue, and the run shows a gap.
5. Come back and open the run › **Fill gaps from the SD card**. The gap closes and an event is logged.
6. `cosmic/phone/<date_name>/minutes.csv` appears on the Mac.
7. Add the "Muon logging" control to Control Center and toggle it. Ask Siri: "What's the muon rate in MuonP4".

## Known limitations

- **Not yet compiled in Xcode.** The code was written and checked on Linux: the Swift core compiles and its tests pass, and every file parses. SwiftUI, ActivityKit and WidgetKit can't be type-checked there. Expect a few small fixes on the first Xcode build.
- **Radio diagnostics** needs a firmware `wifi_status` command. Until then the card says so. If a detector answers the command, its fields are shown.
- The **FPGA bitstream name** shows only if the detector's status reports one. The current firmware does not.
- iOS ends a Live Activity after about 8 hours. Restart it in Settings; logging continues either way.
- Force-quitting the app stops background logging until you open it again. The detector keeps writing its SD card.
- The Live Activity pair-line chart needs the updated app on the phone (older states fall back to bars).

## Roadmap and open questions

- First Xcode build and on-device test pass, then screenshots to replace the mockups.
- Firmware: `wifi_status` (channel, stations, TX power, whether the C6 is actually beaconing) and a bitstream name in `status`.
- Decide whether the custom tab bar stays the default or Apple's system bar takes over (one switch).
- Light mode: currently dark only by design.
- Optional export of a "corrected" series for analysis, computed offline from the stored raw data, never in the live view.
- License: the source repository had no license file, so none is included here yet. The bundled fonts are under the SIL Open Font License 1.1 (see `MuonMonitor/Resources/Fonts`).

## More

- [docs/BLUETOOTH-PROTOCOL.md](docs/BLUETOOTH-PROTOCOL.md): advertising, the 160-byte telemetry packet, commands (v4)
- [docs/USER-GUIDE.md](docs/USER-GUIDE.md): using the app day to day
- [docs/DATA-FORMAT.md](docs/DATA-FORMAT.md): SD-card and exported files
- [docs/HISTORY.md](docs/HISTORY.md): how the app was built and why it looks the way it does
- [docs/history/](docs/history/): v1 screenshots and the original Codex notes
- [design/](design/): mockups, redesign plan, review, design system
