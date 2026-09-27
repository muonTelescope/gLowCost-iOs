# P4 hardware test — 2026-09-26

**Final status:** updated firmware flashed and verified; card seated and logging; encrypted controls, SD download and reconnect passed. Source and verification notes pushed to fork main at `f9327c82de0ec62f5a652a96f5ea7efb1b25efd8`. Device left with synchronized clock, Wi-Fi off, HV settled and physics ready. Physical iPhone testing remains pending.

Flashed source commit `06a7ae9` to the attached ESP32-P4 revision 1.3. The existing C6 firmware was retained. Original full P4 flash backup remains verified and unchanged.

## Flash verification

Bootloader at `0x2000`, partition table at `0x8000`, application at `0x10000`; esptool verified all written hashes. NVS and SD contents were not erased. Application SHA-256: `aba638f847bff6f0de97e0051deca15d6361b16a91e9d824b4693c2db7079faa`.

## Observed first boot

- FPGA DONE high, startup HV byte `0xea`, ten-second settling completed.
- Mac discovered MuonP4 with the service UUID and compact manufacturer data; successive received advertising bursts were about 15 seconds apart (reception is not guaranteed).
- Connected 160-byte GATT reads and short notification tokens worked. The Mac test library can confuse concurrent reads and notifications on the same characteristic; the subsequent polling test avoided this. The iOS decoder handles the two packet types separately; physical iPhone behavior remains untested.
- At firmware uptime 133.139 s: idle 120-second timeout triggered.
- 134.639 s: HV disabled. 134.780 s: Wi-Fi stopped. 137.780 s: HV restored. 147.785 s: settling complete, physics ready.
- Bluetooth remained connected and readable after Wi-Fi deinitialization.
- Setup minutes 1 and 2 did not contribute to physics totals. Minute 3 included 60,000 ms of valid exposure: CH01/CH02/CH12 = 25/18/29, triple = 0, other channels = 152/143/170. Cumulative physics totals matched the first valid minute. Environment: 28.811 °C, 975.50 hPa.
- No repeated boot, panic, watchdog, or brownout message in the 280-second capture. This is not a power-rail or RF noise measurement.
- SD initialization failed before filesystem access (`CMD8`, `ESP_ERR_INVALID_RESPONSE`, 0x108); card status was accurately reported unavailable over BLE. A subsequent software reset also failed SD initialization, this time during SDIO reset (`ESP_ERR_INVALID_ARG`, 0x102). A complete power removal/card reseat was requested; no formatting has been performed.

Physical iPhone pairing, GPS, background logging, Live Activity and Dynamic Island tests remain pending the phone.

## Pairing issue found during testing

The Mac connected and read telemetry, but its first protected control write returned ATT error 15 (Insufficient Encryption). A firmware revision now explicitly initiates security and exchanges encryption/identity keys, with fast connection parameters during initial pairing. The revised image subsequently passed encrypted control testing.

## SD card preparation

At the user's explicit request, the Mac-attached removable card (31,914,983,424 bytes, 62,333,952 sectors, matching the previously observed SL32G capacity) was repartitioned. The old 536.9 MB bootfs FAT32 partition and 31.4 GB Linux partition were removed. The new MBR layout contains one full-size FAT32 `MUONLOG` volume with 16 KiB clusters. macOS filesystem verification returned exit code 0, and the card was safely ejected. No FPGA or configuration files are needed on it: the P4 firmware embeds `main/fpga.bin`. This filesystem preparation alone does not establish the cause of the earlier card-command initialization failures.

## Reseated card and pairing-fix boot

The user confirmed the microSD card had not latched in. After reseating, the P4 successfully initialized the SL32G SDHC card at 10 MHz (30,436 MiB). The pairing-fix application (947,824 bytes, SHA-256 `14fb3cfa0caad690d9b2a22d8f5d4734323b607ce307b55d75456c74c9ce9697`) was flashed at 0x10000 and its written hash verified.

## Final functional results

- Pairing completed with `BLE encryption status=0 encrypted=1`.
- Encrypted status, counts, environment, clock sync, Start Physics Run, file listing, chunked file download and RAM CSV retrieval passed.
- Manual transition: HV off at log timestamp 111.370 s, Wi-Fi off 111.511 s, HV restored 114.511 s, physics ready after settling at 124.516 s. Bluetooth remained connected throughout.
- The downloaded 441-byte CSV contains one setup row and two physics rows. Valid intervals are 60,000 and 60,011 ms. All three rows match the RAM CSV; the overlapping valid row matches all seven full Bluetooth count fields and rounded environmental values. First physics pair counts are 17/11/27; temperature 28.630 °C, pressure 975.588 hPa.
- Status bits confirmed FPGA ready, SD mounted and successful SD count write/flush. No panic, reboot or watchdog message appeared in the 240-second final capture.
- The concurrent scanner saw the service/name and manufacturer payload before the final encrypted RAM response was logged, confirming advertising during a connection. Later advertising observations were about 15 seconds apart.
- An initial 50-second discovery attempt did not find the device. Retrying with case-normalized UUID/name matching succeeded; the exact reason for the miss was not established. Short advertisement windows do not guarantee reception.
- The P4 retains the existing C6 image; no C6 update was needed for these tests.

The app's physical iPhone, GPS, background/Live Activity/Dynamic Island tests remain pending. These tests do not establish BLE interference levels, absolute pulse accuracy, or electrical rail stability. Serial `status` did not return a response, so functional status was verified through Bluetooth instead.

## Reconnect and final state

The convenience scanner timed out on another reconnect. Inspection showed its listener is installed after scan start. A callback installed before scan start discovered MuonP4 and the Mac successfully reconnected and read encrypted status. Reopening the USB serial monitor produced a fresh boot banner despite no explicit reset call, so this successful reconnect also tested a bond across a P4 reboot. The clock was restored; the final encrypted status and telemetry read confirmed Wi-Fi off, transition false, zero settling time and physics ready. All host test clients were disconnected.

## Independent power-bank Wi-Fi check — 2026-09-26T22:40:29.597621+00:00

With USB disconnected from the computer, Bluetooth status on the first battery boot showed uptime 167.136 s, Wi-Fi off, physics ready and FPGA/SD/write status healthy. After the user rebooted, Bluetooth caught a new boot at uptime 89.227 s with Wi-Fi still on. The encrypted `wifi_keep` command succeeded. The Mac System Settings Wi-Fi list then displayed **MuonReadout**, a secure network with **3 of 3 signal bars**. This independently verifies AP visibility from a battery-powered boot; no terminal boot command was required. Wi-Fi was intentionally left held on for this boot so the user can connect. Manual Start Physics Run or a reboot ends that hold; Wi-Fi-on measurements remain non-physics data.

## Follow-up: Wi-Fi visibility lost while held on

After the earlier positive Wi-Fi-list observation, the user reported that neither Mac nor iPhone showed the SSID. A fresh Mac System Settings observation also omitted MuonReadout. Bluetooth confirmed the SAME boot ID (`235986012959454344`) at uptime 319.986 s with `keep_wifi=true`, `wifi_off=false`, no transition, and healthy FPGA/SD/write status. This rules out the application idle timer or a reboot as the explanation for this later disappearance. The P4 software flag does not prove ongoing C6 beacon transmission.

The old airport utility is absent. Repeated CoreWLAN scans returned redacted names; rapid repeats also returned Resource busy, so an empty name-filter result is inconclusive. A directed scan for MuonReadout returned zero results without an error, but privacy redaction still limits interpretation. Read-only Hosted radio diagnostics and AP event logging have been prepared for the next USB-connected trial. Root cause remains unresolved; the earlier positive scan must not be treated as proof of sustained Wi-Fi availability.
