# MuonP4 firmware and iPhone companion

The updated firmware is now flashed and tested on the USB detector. Boot, Wi-Fi shutdown, HV settling, Bluetooth telemetry, encrypted controls, pairing/reconnection, SD writes and log downloads passed. The physical iPhone tests remain pending. See `HARDWARE-TEST.md` for the results.

## What changed

- Wi-Fi setup lasts **120 continuous seconds without an associated Wi-Fi client**, restarting that idle countdown when a client leaves. Keep Wi-Fi On suspends it. A late client during the shutdown grace period cancels automatic shutdown. AP beacons use 100 ms instead of 1,000 ms.
- **Start Physics Run** is available in both the web interface and native app. The existing HV-off → Wi-Fi-off → 3-second hold → HV restore → 10-second settle sequence remains. Only a subsequent full stable minute qualifies as physics.
- All completed minute records preserve raw counts. Appended CSV fields distinguish setup, physics, clock state, sensor validity, Wi-Fi/HV state, sequence, uptime and actual integration duration. Console `counts` is now non-destructive.
- The detector advertises **MuonP4** with a custom service UUID in its primary packet, plus a compact active-scan response containing the latest completed minute's CH01/CH02/CH12 counts, temperature, pressure, sequence and flags.
- Advertising occurs in a **350 ms window roughly every 15 seconds**, with 100 ms packet spacing inside each window. This implements four discovery opportunities per minute despite the legacy Bluetooth interval limit. Reception is not guaranteed. Advertising continues while one phone is connected, using non-connectable scannable packets during that connection.
- A full Bluetooth connection provides **all seven 32-bit minute counts and 64-bit cumulative physics counts**, cumulative valid exposure, boot/session identity, MAC-derived device ID, uptime, temperature, pressure, HV, FPGA, SD mount and last count-write status. No detector battery sensor exists in this source, so no invented battery reading is sent.
- Notifications every 15 seconds tell the phone to read a coherent complete snapshot. Measurement values change after each completed minute; current operating flags and uptime can change between minutes. Small-MTU long reads retain one stable snapshot.
- Read/write control and file-transfer characteristics cover the web interface's features after Wi-Fi is off. HV operations run in a separate worker and hardware changes share a recursive lock with the web/console paths. Controls require an encrypted Bluetooth link; bonding is stored in NVS and pairing explicitly exchanges encryption/identity keys. The no-display **Just Works** pairing method does not provide authenticated MITM protection or an owner-only access policy.
- Connection requests use 945–960 ms intervals with latency 1 at idle, and 15–30 ms with latency 0 during initial pairing and for controls/downloads, reverting after 30 seconds without a command. The central decides actual timing. This is additional radio traffic beyond the advertising windows.

## iPhone application

Open `MuonMonitor/MuonMonitor.xcodeproj` in Xcode. Select your Apple development team for **both** MuonMonitor and MuonLive; use matching unique bundle identifiers if the example identifiers conflict. Build/run on an iPhone with iOS 17 or later. Dynamic Island requires a compatible iPhone. The provided device build is unsigned and is not an installable signed IPA.

1. Open the app near MuonP4 and press **Start Logging**. On the first run it connects to the first matching nearby device; subsequent runs prefer the saved device. Stop logging and use “Use a different detector next time” to change this.
2. Allow Bluetooth and location access. Wait for a connection before locking the phone. GPS collection starts/stops with logging, records fix age/accuracy, and uses the visible background-location indicator. Always permission can be requested in Settings for broader background sessions. Denied/reduced GPS access does not stop detector logging.
3. Use **Detector** for time synchronization, a manual clock, run labels, power controls, HV byte/off, FPGA programming with HV sequencing, startup DAC values, individual DAC channels, live/current/total counts, environmental readings including humidity, current/environment/RAM CSV downloads and previous SD files.
4. **Charts** shows raw and corrected rates, pressure, temperature, and recent minute records. Setup and invalid minutes are excluded from the physics rate chart. Missing sequences break the line; no environmental correction is invented for missed intervals. Cumulative differences recover aggregate counts/exposure across gaps, not the missing minute history. SD remains authoritative.
5. **Settings** lets you edit all supplied correction parameters. **Export phone log** shares JSON Lines with exact raw telemetry, corrected combined rate, coefficient snapshot, recovered count differences, phone GPS, accuracy/age/altitude/speed/course when available, Bluetooth discovery RSSI, phone battery state, OS/model, timezone, thermal and low-power state. RSSI is the last discovery value, not a continuous distance estimate. GPS refers to the phone, not an independently measured detector position.
6. Live Activities show raw last-minute counts and environment on the Lock Screen and Dynamic Island. Stale link/sample data is marked overdue. Use **Restart Live Activity** while the app is open if the system ends it. Force-quitting prevents reliable background resumption until reopening. ActivityKit and location/Bluetooth scheduling remain controlled by iOS.

The chart displays up to 1,440 received records held in memory for the current app process; JSONL exports retain the full logging session. Old exported files are available through Files → On My iPhone → MuonP4. Downloads report success only after all chunks arrive and the final file is saved; failed transfers do not become completed exports. Hardware commands are not automatically retried after a timeout.

## Supplied correction defaults

The user supplied these values from the longest clean external-battery run:

| Parameter | Default |
|---|---:|
| Reference pressure | 982.864 hPa |
| Reference detector temperature | 24.637 °C |
| Pressure coefficient | −0.15 %/hPa |
| Combined CH01+CH02+CH12 temperature coefficient | −0.393 %/°C |
| CH01 temperature coefficient | −0.70 %/°C |
| CH02 temperature coefficient | −0.62 %/°C |
| CH12 temperature coefficient | +0.16 %/°C |

`Ncorrected = Nraw × exp[−βP(P−P0) − βT(T−T0)]`, using **fractional** coefficients internally. Rates divide by actual valid integration duration. There are no supplied temperature fits for CH012 or the three auxiliary channels, so those charts remain raw. Temperature fits are provisional and statistically consistent with zero; the pressure coefficient was chosen on physical grounds, not fitted to this short run. The app labels these limitations and stores the actual settings used with each new logged sample. Editing settings recalculates the visible chart but does not rewrite earlier exported log entries.

## Principal source files

| Area | Location |
|---|---|
| AP timing and thresholds | `firmware-source/main/app_common.h` |
| Idle timer, Start Physics Run, shutdown | `firmware-source/main/web.c` |
| Full-minute validity and cumulative counts | `firmware-source/main/counters.c`, `measurement_window.h` |
| Serialized hardware transitions | `firmware-source/main/hardware.c` |
| CSV metadata and checked count writes | `firmware-source/main/storage.c` |
| Advertising, GATT, connection behavior | `firmware-source/main/ble_broadcast.c` |
| Bluetooth controls and downloads | `firmware-source/main/ble_control.c` |
| Shared wire encoding | `firmware-source/main/telemetry_protocol.h`, `.c` |
| iPhone connection/restoration/logger | `MuonMonitor/App/Monitor.swift` |
| Web-equivalent controls | `MuonMonitor/App/ControlsView.swift` |
| Charts and calibration | `MuonMonitor/App/ChartsView.swift`, `SettingsView.swift`, `Shared/Correction.swift` |
| GPS and phone metadata | `MuonMonitor/App/PhoneMetadata.swift` |
| Live Activity/Dynamic Island | `MuonMonitor/Widget/MuonWidget.swift`, `Shared/MuonActivity.swift` |

## Verification and limits

See `VERIFICATION.md` for exact build/test results and `source-findings.md` for the original firmware investigation. Firmware source is based on repository main `43968f7602fa24662197d2147c77b1c5a8a0d162`; ESP-IDF 5.5.4 and its locked hosted-radio dependencies were used.

The installed C6 firmware supports the tested BLE connection and advertising path; it did not require flashing. Physical iPhone behavior, RF interference and pulse accuracy still need their respective tests. `physics_valid` means the programmed operating-state checks passed, not an experimental RF-noise certification.

Apple references: [background scanning restrictions even with Live Activities](https://developer.apple.com/forums/thread/815189), [Live Activity presentation and lifecycle](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [connection parameter guidance](https://developer.apple.com/library/archive/qa/qa1931/_index.html).
