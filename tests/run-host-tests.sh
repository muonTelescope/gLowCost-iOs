#!/bin/sh
# Host tests for the app's pure-Swift core (no Xcode, no simulator needed).
#  1. Build the firmware's C telemetry encoder and write a reference packet.
#  2. Compile Shared/Telemetry.swift + App/Core/*.swift with the tests and
#     decode that packet, then exercise binning, health, SD-log parsing, etc.
# Works on macOS (Xcode command line tools) and Linux (swift.org toolchain).
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app="$repo/MuonMonitor"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

cc -std=c11 -Wall -Wextra -Werror -I "$repo/tests/protocol" \
   "$repo/tests/protocol/make_fixture.c" "$repo/tests/protocol/telemetry_protocol.c" -o "$out/make-fixture"
"$out/make-fixture" "$out/fixture.bin"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found: install Xcode or a swift.org toolchain to run the Swift tests" >&2
    exit 1
fi
# -Onone keeps assert() active.
swiftc -Onone -module-cache-path "$out/swift-cache" \
    "$app/Shared/Telemetry.swift" "$app"/App/Core/*.swift "$repo/tests/swift/main.swift" -o "$out/swift-test"
"$out/swift-test" "$out/fixture.bin"
