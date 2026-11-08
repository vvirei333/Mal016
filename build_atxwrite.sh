#!/usr/bin/env bash
# build_atxwrite.sh — cross-compile src/atxwrite.m (ImageIO ATX encoder) for iOS 16
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${SDK:-$ROOT/../ABrake27/poc/SDK/iPhoneOS.sdk}"
MINIOS="${MINIOS:-15.0}"
OUT="$ROOT/atxwrite"
mkdir -p "$ROOT/build"
clang -c -target arm64-apple-ios"$MINIOS" -isysroot "$SDK" \
    -fobjc-arc -fmodules -O2 -o "$ROOT/build/atxwrite.o" "$ROOT/src/atxwrite.m"
ld64.lld -arch arm64 -platform_version ios "$MINIOS" 16.5 -syslibroot "$SDK" \
    -framework Foundation -framework CoreGraphics -framework ImageIO -framework CoreFoundation \
    -lobjc -lSystem -e _main -o "$OUT" "$ROOT/build/atxwrite.o"
command -v ldid >/dev/null && ldid -S "$OUT"
echo "[+] built: $OUT  (install to /var/jb/usr/bin — /var/tmp is not in the trust cache)"
