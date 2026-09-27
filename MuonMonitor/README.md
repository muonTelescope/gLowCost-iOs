# MuonP4 iPhone app (v2)

A native iOS 26 app for the gLOWCOST MuonP4 detector: live counts, a saved history of runs, GPS tracks, SD-card merging, alerts, Live Activity, Dynamic Island, Home Screen widgets and Control Center controls. Counts are stored **raw**; pressure and temperature are recorded with every minute and no correction is applied in the app (the detector compensates SiPM bias for temperature itself).

No server, no paid Apple Developer membership and no third-party packages are needed.

## What it does

| Area | Features |
|---|---|
| **Now** | Last completed minute drawn as muon tracks, three pair counts, last hour (one bar per minute, gaps visible), pressure and 3-hour trend, detector temperature, session totals, counting-statistics check, plain-language explainer |
| **Runs** | Every logging session saved on the phone (SwiftData). Rename, default and custom tags, notes, filter by tag, search, compare two runs |
| **Run detail** | Rate chart with 1/10/30/60-minute bins and ±1σ, event markers, scrubbing; pressure, temperature and altitude charts; GPS track coloured by rate; health; SD gap fill; CSV share |
| **Detector** | Health checklist, Start physics run, keep Wi‑Fi on, clock sync, rename the run on the detector, list and download SD files (downloads import automatically) |
| **Expert console** | HV byte, DAC channels, FPGA reload, raw counters, telemetry flags (Settings › Expert mode) |
| **Saving** | Pick iCloud Drive › cosmic once. Runs are written to `cosmic/phone/<date_name>/minutes.csv` and `run.json` every 5 minutes |
| **Outside the app** | Live Activity with a Stop button, Dynamic Island (counting, setup countdown, overdue), Home and Lock Screen widgets, Control Center toggle and Physics-run button, Siri/Shortcuts ("What's the muon rate in MuonP4") |
| **Alerts** | Local notifications: updates stopped, three zero minutes, sudden jump, SD card unmounted, noisy counting |

### Renaming a run

Renaming the **live** run also sends the name to the detector as its run label (letters, digits, `-` and `_`; spaces become `_`; up to 32 characters). The firmware renames the active `muon_…` and `env_…` files on the SD card to end in that label. Renaming a finished run changes the app and the cosmic folder only.

### Counting-statistics check

For each pair the app compares minute-to-minute scatter with pure counting chance (variance ÷ mean after removing slow drift; 1.00 is ideal). On your existing logs every clean run scores 0.90–1.04. The Sep 23 mains run with Wi‑Fi on scores 1.29 on CH02, the channel that picked up interference.

## Build and run (free Apple account)

You need a Mac with **Xcode 27** and an iPhone on **iOS 26 or later** (Dynamic Island: iPhone 14 Pro or newer).

1. Open `Config.xcconfig` and set `MUON_BUNDLE_ID` to something unique to you (for example `com.yourname.muonp4`).
2. Open `MuonMonitor.xcodeproj`. In Xcode › Settings › Accounts add your Apple ID; it creates a free **Personal Team**.
3. Select the **MuonMonitor** target › Signing & Capabilities › Team: your Personal Team. Do the same for **MuonLive**.
4. Connect the iPhone, enable **Developer Mode** (Settings › Privacy & Security), choose it as the run destination and press Run.
5. On the phone: Settings › General › VPN & Device Management › trust your developer certificate the first time.
6. In the app: Settings › Saving › Folder → choose **iCloud Drive › cosmic**.

Free-account limits: the app must be reinstalled from Xcode every **7 days**; at most 3 apps signed this way per device.

**If Xcode cannot register the App Group** (the error mentions `group.…`), empty `MUON_APP_GROUP`, `MUON_APP_ENTITLEMENTS` and `MUON_WIDGET_ENTITLEMENTS` in `Config.xcconfig`. Everything still works except that Home Screen widgets and the Control Center toggle cannot see live data. The Live Activity and Dynamic Island do not need the group.

The cosmic folder uses a security-scoped bookmark, not the iCloud entitlement, so it works without a paid membership.

## Simulator and demo data

Choose the **MuonMonitor Demo** scheme to launch with `--demo`: two synthetic runs (a stationary 18-hour run and a moving run with altitude) marked "Demo data". Bluetooth, the Live Activity from a real detector, widgets with live data, and iCloud need a real iPhone.

## Tests

```sh
../tests/run-host-tests.sh
```

Runs the C protocol test and, on a Mac, the Swift host tests: wire compatibility, run-label sanitising (mirrors the firmware), SD parsing for old and new firmware, gap filling, health statistics, binning and CSV export.

## Hardware test checklist

1. Pair: Runs are empty → Now › Find a detector → Connect and start logging. iOS may ask to pair.
2. First minute appears within ~2 minutes; setup countdown shows in the Dynamic Island.
3. Rename the live run to "Test run". Detector › status shows label `Test_run`; the SD file ends in `_Test_run.csv`.
4. Lock the phone for 30 minutes. The Live Activity updates each minute; the phone keeps logging.
5. Walk out of range for 5 minutes: an "updates stopped" alert arrives, the Island shows overdue, the run shows a gap.
6. Come back, open the run › Fill gaps from the SD card. The gap closes and an event is logged.
7. Settings › Saving: `cosmic/phone/<date_name>/minutes.csv` appears on the Mac.
8. Control Center: add "Muon logging"; toggle it. Siri: "What's the muon rate in MuonP4".

## Project layout

| Path | Contents |
|---|---|
| `App/Core` | Pure Swift: minute records, SD parsing, health, binning, CSV (host-tested) |
| `App/Model` | SwiftData models and tag catalogue |
| `App/Services` | Bluetooth link, app state, location, cosmic folder, alerts, Live Activity, demo data |
| `App/Views` | SwiftUI screens |
| `Shared` | Code used by the app and the widget extension |
| `Widget` | Live Activity, Dynamic Island, widgets, Control Center |
| `tools/generate_project.py` | Regenerates the Xcode project after adding files |

Protocol details: `../docs/bluetooth-protocol.md`.
