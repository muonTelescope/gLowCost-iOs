# Source and binary findings — ESP32-P4 Muon readout

Inspected repository: https://github.com/tharinduudu/ESP32-P4-gLOWCSOT-cubesat

- Main commit: `43968f7602fa24662197d2147c77b1c5a8a0d162`.
- Legacy branch: `legacy-readout-p4-quiet-restart`, commit `2e27d882989a4890af55434b6d9614d4e8b2e682`.
- Clone location: a local clone of `ESP32-P4-gLOWCSOT-cubesat`.
- Espressif hosted driver: registry version 1.4.7, published commit `d24d1dc3f709965fa61e3a1304c0896a9f3d497c`. Source extracted into `work/esp-hosted-1.4.7` in the same task directory. This is the version specified by the repository lockfile; an exact installed driver version cannot be established from source alone.

## Installed application

The active image is at flash offset `0x10000`. Project: `p4_muon_readout`; version: `1`; build stamp: `Jun 16 2026 11:55:04`; ESP-IDF identifier: `HEAD-HASH-NOTFOUND`. ELF SHA-256: `ee95bcdc322b4fcb44489f484783a8782cdb94824136845adf2f09a9e6cf8163`. The bootloader is stamped `Jun 16 2026 11:44:29`.

The application image checksum and appended validation SHA-256 both validate. The validation SHA-256 is `32af4c493b229cd8fd1a6c5e5754f35424566f4ebf677505f72fbb64e16e61de`. This verifies image integrity, not identity with a particular source commit.

The binary refers to `./main/main.c`, has the older console help/status format, and has no `MuonP4` or BLE-display strings. Its embedded 7,334-byte FPGA bitstream matches the repository's `main/fpga.bin` exactly at application offset `0x27a78` (decimal 162424). It is consistent with an older monolithic variant, not the current modular BLE build. Its exact originating commit is unproven.

### Actual auto-off delay

The task creation at `0x4001fe44–0x4001fe68` passes the name at `0x4008cb58` (`auto_power_save_task`) and entry point `0x4001a3b0`.

At that entry point, `c.lui a0,5` and `addi a0,a0,-0x1e0` load `0x4e20 = 20,000` ticks before the delay call at `0x4001a3c8`. The later loop loads `0x7530 = 30,000` ticks. The repository's tick rate is 1,000 Hz; live log timing provides the additional check of elapsed seconds. See `installed-auto-off-disassembly.txt`.

The AP setup at `0x4001a94c` onwards constructs the literals `MuonReadout` and `glowcost` as immediate values. It sets channel 6, maximum one client, and beacon interval 1,000. The password therefore is not present as a contiguous ASCII string in this optimized binary. See `installed-ap-config-disassembly.txt`.

## Main branch behavior and exact locations

- `main/app_common.h:131–135`: SSID, password, channel, and **7,000 ms** auto-off constant. The 4-client macro is overridden by the actual AP configuration.
- `main/main.c:28–38`: HV off, volatile FPGA configuration, DAC setup, HV restore and 10-second settle before Wi-Fi starts.
- `main/main.c:65–71`: Wi-Fi, HTTP, BLE, then the auto-off task. The timer is not measured from power-on.
- `main/web.c:792–823`: initial setup delay, then check `s_power_save_mode`, `s_wifi_keep_on`, and `s_wifi_clients`. Zero clients with keep-on false triggers shutdown. With clients or keep-on set, checks repeat every 30 seconds; this is not a timer that restarts for 7 seconds after every disconnect.
- `main/web.c:747–759`: marks power-save mode immediately, then starts the shutdown task.
- `main/web.c:689–743`: wait 1.5 seconds; turn HV off; stop HTTP; stop and deinitialize Wi-Fi; keep HV off for 3 seconds; restore its prior byte; settle; allow idle CPU down to 40 MHz. Light sleep is disabled at line 674. No normal ESP32 reboot is requested here.
- `main/hardware.c:412–439`: disable counting and clear live counters around HV transitions, then wait 10 seconds after nonzero HV before enabling counting again.
- `main/web.c:776–787`: Keep Wi-Fi On changes a RAM flag for the current boot. No persistent preference is saved.
- `main/web.c:827–845`: client association/disassociation events maintain the client count.
- `main/web.c:867–883`: channel 6, one client, beacon interval 1,000, WPA/WPA2 PSK. A second device cannot join while the single slot is occupied. The long beacon interval can make discovery slow.
- `main/counters.c:101–108`: minute count printing is suppressed in power-save mode. Quiet serial output alone is not proof that the CPU stopped.
- `main/console.c:60–106`: no Wi-Fi restart or keep-on serial command. `counts` resets counters, so it was not used for this read-only diagnosis.

After automatic shutdown there is no application path that brings the AP back during the same boot. The web endpoint `/api/wifi_keep_on?enable=1` must be reached while Wi-Fi is still running. Once shutdown is scheduled, its task does not re-check keep-on or newly arriving clients during the 1.5-second grace period.

## Repository history matters

The initial imported firmware and pre-BLE modular versions use 20 seconds. Commit `00eaa55` changes it to 7 seconds while adding BLE. Main commit `43968f7` fixes startup order to initialize the hosted radio before BLE.

The separate legacy branch changes the timer back to 20 seconds and disables BLE in `d251122`. Its `main/web.c` also reconfigures the FPGA and reloads the DAC after Wi-Fi shutdown, with HV off. That is a detector restart, not an ESP32 reboot. Those extra post-shutdown FPGA/DAC messages are absent from the installed active binary.

## P4/C6 separation and reset paths

ESP32-P4 has no native Wi-Fi. The Waveshare module provides an ESP32-C6 radio over SDIO. Repository `sdkconfig:2758–2785` selects C6, 4-bit SDIO at 40 MHz, reset GPIO54, CMD19/CLK18/D0–D3 on GPIO14–17. The only USB serial device detected during this examination is connected to the P4; a P4 flash backup does not include the C6's separate firmware or the SD card.

In hosted driver 1.4.7:

- `host/api/src/esp_hosted_api.c:191–219`: Wi-Fi init brings the transport up; stop/deinit issue radio RPCs, not a host reset or board power cut.
- `slave/main/slave_control.c:793–823`: C6 RPC handlers call `esp_wifi_deinit()` and `esp_wifi_stop()`.
- `host/drivers/transport/transport_drv.c:64–82,121–147`: startup/reconnection toggles the configured C6 reset line and retries transport establishment. It logs failure every ten retries, with up to 1,000 retries.
- `host/drivers/transport/sdio/sdio_drv.c:306–323,478–488`: repeated unresponsive-buffer or write failures explicitly restart the host. These error strings also appear in the installed binary. Line 832 is another restart path, but it is excluded by this source's `DO_COMBINED_REG_READ=1`; it should not be reported as an active path for this configuration.
- `host/port/src/os_wrapper.c:771–775`: the restart callback calls `esp_restart()`.

These mechanisms can cause boot loops if the transport fails; their existence alone does not demonstrate a failure on this device.

Repository watchdog settings: bootloader WDT 9 seconds (`sdkconfig:657–659`), interrupt WDT 300 ms (`1796–1798`), task WDT 5 seconds with panic disabled (`1799–1804`), and brownout detection enabled (`1636–1641`). The bootloader watchdog is configured to be disabled before user code; the 10-second HV settle uses `vTaskDelay`, allowing other tasks to run. These settings alone do not establish the cause of a reset in the installed build.

External references: [Espressif P4 Wi-Fi expansion](https://docs.espressif.com/projects/esp-idf/en/stable/esp32p4/api-guides/wifi-expansion.html), [Waveshare module architecture](https://www.waveshare.com/wiki/ESP32-P4-Module), [published hosted driver 1.4.7](https://components.espressif.com/components/espressif/esp_hosted/versions/1.4.7/readme?language=en).

## Verified full flash backup and restored application behavior

The full 16 MiB P4 image was saved privately with a manifest and SHA256SUMS. It is not part of this repository.

SHA-256: `e764944a476ab7985d88f929bff93967650db5b2c32f66773f74cca03e7e0001`.

Each nonblank 1 MiB block was read at 115200 baud and checked against the device's MD5. Blocks at 7, 8, 14 and 15 MiB were reconstructed as erased bytes only after their device hashes matched an all-FF block. The final complete local image also matched a full-device MD5. Old nonblank bytes outside the active application were preserved. `backup-manifest.json` records the method and hashes. No flash or eFuse write commands were issued. The backup temporarily reset the CPU into its bootloader and ran esptool's RAM helper, then reset it back into the original application.

The restored boot capture, `serial-restored-timing.log`, shows:

| Uptime in firmware log | Observed event |
|---|---|
| 0.370 s | HV off |
| 0.389 s | FPGA DONE high |
| 0.394 s | HV byte EA, begin 10 s settle |
| 10.399 s | Startup HV enable completed |
| 37.463 s | No Wi-Fi client after setup window; scheduled shutdown |
| 38.963 s | HV off, HTTP/Wi-Fi shutdown |
| 39.101 s | Wi-Fi off, hold HV off for 3 s |
| 42.101 s | HV EA restored; begin 10 s settle |
| 52.106 s | Power-save mode active; detector logging continues |

No repeated boot banner, watchdog reset, brownout, or transport-failure reset appeared in the 125-second restored-boot capture. The AP startup timestamp was not printed at this logging level; the 20-second constant is established by the installed binary's disassembly, not by subtracting an unavailable AP log timestamp. A read-only `status` console command at the end produced no reply. The application logged that counting resumed, but this capture did not independently verify SD writes or pulse rates.

Conclusion: deliberate firmware shutdown is directly observed. The installed image uses an older 20-second window, whereas current repository main uses 7 seconds. Neither observation demonstrates an electrical power-supply failure. Earlier high counts could involve RF coupling, but neither this flash image nor the short serial capture measures that interference.

## Modified source is separate from the installed device

`firmware-source/` contains the requested changes on branch `fix/wifi-setup-and-minute-telemetry`; it has not been flashed. Original source line references above refer to pristine commit `43968f7`, retained in `repository-main-43968f7.zip`. See `IMPLEMENTATION.md` for the changed files, protocol and application behavior.
