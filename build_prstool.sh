#!/usr/bin/env bash
# build_prstool.sh — PRSService (PosterBoardServices) client for iOS 16.x
# NOTE: must be signed ON DEVICE with src/prs.entitlements:
#   ldid -Ssrc/prs.entitlements prstool2
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${SDK:-$ROOT/../ABrake27/poc/SDK/iPhoneOS.sdk}"
MINIOS="${MINIOS:-15.0}"
clang -c -target arm64-apple-ios"$MINIOS" -isysroot "$SDK" -fobjc-arc -fblocks -fmodules -O2 \
    -o "$ROOT/build/prstool2.o" "$ROOT/src/prstool2.m"
ld64.lld -arch arm64 -platform_version ios "$MINIOS" 16.5 -syslibroot "$SDK" \
    -framework Foundation -framework CoreFoundation -lobjc -lSystem -e _main \
    -o "$ROOT/prstool2" "$ROOT/build/prstool2.o"
echo "[+] built: $ROOT/prstool2 (sign on device with ldid -Ssrc/prs.entitlements)"
