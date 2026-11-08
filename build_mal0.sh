#!/usr/bin/env bash
# build_Mal0.sh — Linux cross-compile of src/mal0.m → Mal0
# Same pipeline as ABrake27 build_probe.sh (clang → ld64.lld → ldid).
# Output: standalone arm64 CLI — push to device:
#   scp Mal0 root@<iphone>:/usr/bin/  (via Dopamine ssh)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="${SDK:-$ROOT/../ABrake27/poc/SDK/iPhoneOS.sdk}"
MINIOS="${MINIOS:-15.0}"
OUT="$ROOT/Mal0"

have(){ command -v "$1" >/dev/null 2>&1; }
have clang || { echo "[x] clang missing"; exit 1; }
have ld64.lld || { echo "[x] ld64.lld missing"; exit 1; }
[ -d "$SDK/System/Library/Frameworks" ] || echo "[!] SDK missing at $SDK — set SDK=... env"

mkdir -p "$ROOT/build"
clang -c -target arm64-apple-ios"$MINIOS" -isysroot "$SDK" \
    -fobjc-arc -fmodules -O2 -o "$ROOT/build/Mal0.o" "$ROOT/src/mal0.m"

ld64.lld -arch arm64 -platform_version ios "$MINIOS" 16.5 \
    -syslibroot "$SDK" \
    -framework Foundation -framework CoreFoundation \
    -lobjc -lSystem \
    -e _main -o "$OUT" "$ROOT/build/Mal0.o"

if have ldid; then ldid -S "$OUT"; fi
echo "[+] built: $OUT"
echo "[i] install: scp $OUT root@<ip>:/usr/bin/Mal0 && ssh root@<ip> chmod +x /usr/bin/Mal0"
