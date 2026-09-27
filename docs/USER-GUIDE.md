# User guide (app v2)

Build and install: see the [README](../README.md#build-and-run). The design mockup the app follows has Now, Runs, Run detail, Detector, Expert console, Settings, pairing, Lock Screen, Dynamic Island and widget screens.

## First run

1. Power the detector. It advertises as **MuonP4** every 15 seconds.
2. Open the app › **Find a detector** › **Connect and pair**. No detector at hand? Tap **Try the demo instead**. iOS may ask to pair; pairing encrypts detector commands.
3. Allow location so each minute carries its GPS fix.
4. Settings › Saving › choose **iCloud Drive › cosmic**.

## During a run

- **Now** shows the last completed minute as muon tracks, the three pair counts, the last hour (one bar per minute; grey dashes are missed minutes), pressure with its 3-hour trend, detector temperature and physics-only session totals.
- The **logging bar** above the tab bar shows the run name and elapsed time on every tab, with a stop button.
- Lock the phone. The **Live Activity** shows the count, the last 30 minutes, pairs, pressure and temperature, and a **Stop logging** button. The **Dynamic Island** shows the count, a countdown while the detector is in setup, and an overdue state once no minute has arrived for the time set under Settings › Alerts (default 3 minutes).
- Before physics starts the detector keeps Wi‑Fi on for 120 s. **Detector › Start physics run** skips the wait.

## Names and tags

- Tap the pencil on a run to rename it. For the live run, **Rename on the detector too** sets the detector's run label, which renames the active SD files (`muon_…_<label>.csv`, `env_…_<label>.csv`). Labels keep letters, digits, `-` and `_`; spaces become `_`; 32 characters at most.
- Tags come in groups (Power, Radio, Place, Purpose) plus your own. Custom tags are remembered for later runs. Filter the Runs list by tag or search by name.

## Charts and tracks

- Rates are raw counts per minute, divided by the real integration time. Choose 1, 10, 30 or 60-minute bins; bands show ±1σ counting error. Gaps stay gaps.
- Dashed markers show events: reboots, Wi‑Fi and HV changes, missed minutes, SD fills, jumps.
- Drag on a chart to read a bin; the map marker moves to where the detector was at that time.
- The map joins one GPS fix per minute, coloured by rate. A stationary run shows a small cluster inside the typical GPS accuracy circle. Runs that change altitude also show an altitude chart; muon rates rise with altitude.
- No pressure or temperature correction is applied. The detector adjusts SiPM bias for temperature itself, and pressure and temperature are stored with every minute for analysis.

## Counting statistics

For each pair the app compares minute-to-minute scatter with pure counting chance (variance ÷ mean after removing slow drift). 1.00 is ideal. Values well above 1 suggest interference, a noisy threshold or a setup change. Clean runs so far scored 0.90–1.04; the Sep 23 mains run with Wi‑Fi on scored 1.29 on CH02.

## SD card

- **Run detail › Fill gaps from the SD card** (live run) downloads the active SD log over Bluetooth and adds only the minutes the phone missed, marked `source = sd`.
- **Runs › Import** takes `muon_….csv` files (with their `env_….csv` for older firmware) from Files or from anywhere in your cosmic folder. A file that overlaps a phone run fills its gaps; otherwise it becomes its own run.
- **Detector › Files on the SD card** lists and downloads files; muon logs are imported automatically.

## Alerts

Local notifications, each at most once every 30 minutes: updates stopped (Settings › Alerts › **Alert when updates stop**, after 2, 3, 5, 10, 15 or 30 minutes; default 3), three zero-coincidence minutes, a sudden jump (more than 6σ from the recent median), SD card unmounted, noisy counting. Turn each on or off in Settings.

## Outside the app

- Home Screen widgets (small, medium) and Lock Screen widgets (circular, rectangular, inline).
- Control Center: **Muon logging** toggle and **Physics run** button. Both open the app, because Bluetooth runs in the app.
- Siri and Shortcuts: "What's the muon rate in MuonP4", "Start logging in MuonP4", "Stop logging in MuonP4".

## Limits

- iOS ends a Live Activity after about 8 hours; restart it in Settings. Logging continues.
- Force-quitting the app stops background logging until it is opened again. The detector keeps writing its SD card.
- With a free Apple account the app must be reinstalled from Xcode every 7 days.
