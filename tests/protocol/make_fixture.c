// Encodes one reference telemetry packet with the firmware's own encoder
// (telemetry_protocol.c, vendored from the gLowCost firmware) and writes it to
// argv[1]. The Swift tests decode it, which proves both sides agree on the
// 160-byte v4 wire format.
#include <assert.h>
#include <stdio.h>
#include "telemetry_protocol.h"

int main(int argc, char **argv) {
    telemetry_sample_t t = {.boot_id = 0xFEDCBA9876543210ULL, .sequence = 4000000000U, .flags = 127,
        .sample_uptime_ms = 120000, .uptime_ms = 120010, .physics_exposure_ms = 60000, .interval_ms = 60000,
        .temp_millic = -12345, .pressure_pa = 98286, .epoch = 1790000000, .status = 7, .hv = 234};
    for (int i = 0; i < 7; i++) { t.totals[i] = (1ULL << 40) + i; t.counts[i] = 100 + i; t.device_id[i % 6] = (uint8_t)i; }
    uint8_t packet[TELEMETRY_SIZE];
    telemetry_encode(&t, packet);
    assert(packet[0] == 'M' && packet[1] == 'P' && packet[2] == 4 && packet[3] == 127);
    assert(packet[4] == 0x10 && packet[11] == 0xfe);
    assert(packet[56 + 5] == 1 && packet[55] == 0 && packet[159] == 0);
    assert(packet[112] == 100 && packet[136] == 106);
    if (argc > 1) {
        FILE *f = fopen(argv[1], "wb");
        assert(f);
        assert(fwrite(packet, 1, sizeof(packet), f) == sizeof(packet));
        fclose(f);
    }
    puts("PASS: C encoder produces the reference v4 packet");
    return 0;
}
