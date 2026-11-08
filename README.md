# Mal016 — PosterBoard lab & CLI for jailbroken iOS 16.x

Jailbreak utility / research kit (Dopamine, root) — **no exploits**. Mal016 uses
the root access you already have. Target: iPhone 8 Plus (iPhone10,5),
iOS 16.7.16 (20H392).

Goal: make community `.tendies` wallpaper packs work on iOS 16.x.

## Current status (2026-11-09)

**Working**
- Gallery tile injection: a pushed `ATXFaceGalleryItem` (via PRSService XPC)
  plus a local descriptor with a generated `SNAPSHOT_GALLERY-*.atx` shows up as a
  tile in the wallpaper gallery, with our art, and is tappable.
- On-device ATX writer via ImageIO (`com.apple.atx`), pixel-perfect round trip.

**Blocked / open**
- "Apply" creates a poster configuration, but from a **native** descriptor —
  a hand-placed descriptor is not registered by the daemon
  (`ProviderInfo.plist` ordering is derived and rewritten).
- `.tendies` packs are iOS 17 format (`ParameterizedCA`), which does not exist
  in the iOS 16.7.16 dyld cache at all. A converter to iOS 16
  `LayeredAnimation` exists (`tools/convert_tendie.py`, v1) but is not yet
  validated because of the registration issue above.

Full mechanism, measured formats and next steps:
**[docs/TENDIES16_MECHANISM.md](docs/TENDIES16_MECHANISM.md)**.
Chronological log: **[HANDOFF.md](HANDOFF.md)** (sessions 1–5).

## Commands (Mal016 CLI, v0.1)

    Mal016 recon                 # identity + paths (RECON-first!)
    Mal016 gestalt dump|get K|set K V|rm K
    Mal016 gestalt backup|restore
    Mal016 tendie inspect X.tendies
    Mal016 tendie import X.tendies [--reset]

(`tendie import` is the goal of the project and is not finished yet.)

## Companion tools (built by this repo)

| Tool | What it does |
|---|---|
| `atxwrite` | PNG/JPEG → Apple ATX texture (tile snapshot), via ImageIO |
| `atx2png` | ATX → PNG (our own files; native hardware snapshots fail) |
| `prstool2` | PRSService XPC client: `fetch`, `dump`, `push`, `additem` gallery items |

Sources: `src/atxwrite.m`, `src/atx2png.m`, `src/prstool2.m`.
Build scripts: `build_atxwrite.sh`, `build_prstool.sh`, `build_mal016.sh`.
Deploy to `/var/jb/usr/bin` (Dopamine's trust cache rejects `/var/tmp`).
`prstool2` must be signed **on the device**:
`ldid -Ssrc/prs.entitlements /var/jb/usr/bin/prstool2`.

## Log
Documents/Mal016.log; header always: `hw.machine` + `kern.osrelease`
(logs without identity are unattributable).

## Build
Linux cross-compile: `clang` → `ld64.lld` → `ldid`, SDK shared with ABrake27
(`../ABrake27/poc/SDK/iPhoneOS.sdk`). See the `build_*.sh` scripts.

## Repo layout
- `src/` — CLI + helper sources
- `tools/` — Python helpers (`convert_tendie.py`)
- `docs/` — technical notes (`TENDIES16_MECHANISM.md`, session-1 log)
- `research/` — native samples (emoji snapshot, clean Duet gallery stream)
- `packs/` — `.tendies` packs + `fetch_packs.sh` (SerStars catalog)

## References
- SerStars/Nugget-Wallpapers — open `.tendies` catalog (111+ packs)
- leminlimez/CowabungaLite — partial-restore architecture (iOS 15+, no tendies)
- YangJiiii/3105 — PosterBoard lab on 17+ (Geod-MCM), feature reference
- ABrake27 research/intel/mcm/BQ272_MCM.md — our MCM surface diff
- ABrake27 research/intel/ma_decomp/ — ImageIO ATX decompiles (ATX container,
  watermark checks)
