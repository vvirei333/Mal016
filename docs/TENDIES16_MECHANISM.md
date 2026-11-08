# Tendies on iOS 16.7.16 — mechanism, tools, and open questions

Status: **2026-11-09** (end of session 5). Device: iPhone10,5 (iPhone 8 Plus),
iOS 16.7.16 (20H392), Dopamine rootless jailbreak, root over USB SSH
(`iproxy 2222 22`, password `thor`).

This file is the technical reference. The chronological log is in `HANDOFF.md`.
Read this first if you are picking the project up.

---

## 1. TL;DR

| Piece | Status |
|---|---|
| Add a tile to the wallpaper gallery | ✅ works (PRSService XPC push + local descriptor + generated `.atx`) |
| Tile art | ✅ works (ImageIO writes a valid ATX snapshot on-device) |
| Apply a tile → create a poster config | ⚠️ creates a config, but **not from our descriptor** (see §6) |
| Render a tendie wallpaper (iOS 17 `ParameterizedCA`) | ❌ impossible on 16.7.16 as-is — string is absent from the whole dyld cache |
| Convert iOS 17 pack → iOS 16 `LayeredAnimation` | ❌ v1 converter written, not yet validated (blocked by §6) |

**Next single question:** how does 16.7.16 register a descriptor so that
"apply" builds a config from it? Everything else depends on the answer.

---

## 2. PosterBoard data store (16.7.16)

Root (inside SpringBoard's data container):

```
/var/mobile/Containers/Data/Application/<SB-uuid>/Library/Application Support/
  PRBPosterExtensionDataStore/59/
    Extensions/<provider-bundle-id>/
      ProviderInfo.plist            # derived: descriptor ordering (daemon-written)
      descriptors/<UUID>/           # instance descriptors
      staticdescriptors/<UUID>/     # provider-static descriptors
      configurations/<UUID>/        # created poster instances
    GalleryCache/<timestamp>.plist  # cached ATXFaceGalleryConfiguration response
    SelectedConfigurationIdentifier.plist
    SwitcherConfigurationOrdering.plist
```

Provider used for tendies: `com.apple.WallpaperKit.CollectionsPoster`.

Descriptor layout:

```
<UUID>/
  com.apple.posterkit.provider.descriptor.identifier   # slug, e.g. "7420"
  providerInfo.plist                                   # often an empty NSKeyedArchiver
  versions/<N>/
    contents/
      <id>.<name>-414w-736h@3x~iphone.wallpaper/
        Wallpaper.plist
        *.ca/                    # CoreAnimation package(s)
      com.apple.posterkit.provider.contents.[...].plist
    supplements/0/...
    SNAPSHOT_GALLERY-withHeader-PROPERTIES<sha>.atx     # gallery tile art
```

Configurations (created when a wallpaper is applied):

```
configurations/<UUID>/versions/0/
  contents/...                       # copy of the descriptor content used
  RuntimeSnapshot-lock.atx / -home.atx
  SNAPSHOT_SWITCHER_*.atx
  RuntimeSnapshotMetadata-*.plist
  com.apple.posterkit.provider.instance.*.plist
```

`.atx` files are Apple **ATX** textures — see §4.

---

## 3. Gallery injection (the working half)

### 3.1 How the gallery is built
The "Добавление новых обоев" gallery is `ATXFaceGalleryConfiguration`
(8 sections, items keyed by `descriptorIdentifier` + `extensionBundleIdentifier`).
It is persisted in the Duet stream

```
/var/mobile/Library/DuetExpertCenter/streams/faceGallery/local/815610501801543
```

and cached as `59/GalleryCache/<timestamp>.plist` (NSKeyedArchiver of the
configuration object). **Placing a descriptor on disk does not add a tile.**
An item must exist in the catalog.

### 3.2 PRSService XPC client
`PosterBoardServices.framework` exposes `PRSService`, which talks to the daemon
over BaseBoard's `BSServiceConnection` (mach `com.apple.posterboardservices`).
An external root process is accepted **only if signed with the right
entitlements**; otherwise every call fails with
`BSServiceConnectionErrorDomain Code=3 "XPC error received on message reply handler"`.

Working entitlement set (`src/prs.entitlements`):

```
com.apple.posterboardservices
com.apple.posterboardservices.services
com.apple.posterboardservices.dataModel
com.apple.posterboardservices.data-store
com.apple.posterboardservices.data-store.refreshConfigurations
com.apple.posterboardservices.data-store.deleteConfigurations
com.apple.posterboardservices.data-store.deleteDescriptors
com.apple.posterboardservices.data-store.refreshConfigurationSnapshot
com.apple.posterboardservices.data-store.mutateSwitcherConfiguration
com.apple.posterboardservices.data-store.accessSwitcherConfiguration
com.apple.posterboardservices.data-store.mutateSwitcherFocusConfiguration
com.apple.posterboardservices.data-store.accessSwitcherFocusConfiguration
com.apple.posterboardservices.data-store.deleteDataStore
com.apple.posterboardservices.data-store.migration
com.apple.posterboardservices.active-wallpaper-observer
```

(The names were extracted from the `__const` cfstrings in PosterBoardServices;
`_PRSServerAccessEntitlement` = `com.apple.posterboardservices.data-store`.)

Signing note: **sign on the device** with
`ldid -Ssrc/prs.entitlements /var/jb/usr/bin/prstool2`. A PC-side `ldid -S`
signature got the binary SIGKILLed by AMFI; the same binary re-signed on device
runs fine. Binaries must live under `/var/jb` (not `/var/tmp`).

### 3.3 Useful PRSService methods
Declared by the framework (completion signatures from the method encodings):

```objc
- (void)fetchGallery:(void (^)(ATXFaceGalleryConfiguration *, NSDate *, NSError *))c;
- (void)retrieveGallery:(void (^)(ATXFaceGalleryConfiguration *, NSDate *, NSError *))c;
- (void)pushPosterGalleryUpdate:(ATXFaceGalleryConfiguration *)cfg
                     completion:(void (^)(NSError *))c;
- (void)refreshSnapshotForGalleryItemsMatchingDescriptorIdentifier:(NSString *)did
                                                extensionIdentifier:(NSString *)ext
                                                        completion:(void (^)(NSError *))c;
- (void)fetchPosterConfigurations:(void (^)(NSArray *, NSError *))c;
- (void)fetchSelectedConfiguration:(void (^)(ATXPosterConfiguration *, NSError *))c;
```

`src/prstool2.m` implements `fetch`, `dump`, `push`, `additem <plist> <slug> [uuid]`.
`additem` deep-copies the first WK item, sets `descriptorIdentifier = SLUG.DYNAMIC`,
optionally forces `identifier` (UUID), appends it to its section and pushes.

**Push semantics:** additive/merge into the persisted catalog; it survives
respring. Pushing an older configuration back does **not** remove items.
To revert: restore the Duet stream from a byte copy and clear `GalleryCache`,
then respring. A pristine stream copy is kept at
`research/duet_facegallery_pristine.bin` (`/var/tmp` gets purged by iOS).

### 3.4 Verified results
- TEST1 art tile appeared in "Коллекции" and was tappable.
- Wallpaper packs (RollingHills) produced tiles with their preview art.
- `fetch` after respring still contained the pushed items.

---

## 4. ATX snapshot format (tile art)

Container: magic `AAPL\r\n\x1a\n`, then chunks `[u32 payloadLen][4cc tag][payload]`.

```
HEAD (0x54 bytes)
  0x00 u32 version = 1
  0x04 12 bytes zero
  0x10 u32 0x93b0 (const)
  0x14 u32 0x1908 (const)
  0x18 u32 width
  0x1c u32 height
  0x20 u32 1
  0x24 u32 0
  0x28 u32 1
  0x2c u32 1
  0x30 u32 0|1 (writer-specific)
  0x34 u32 0
  0x38 u32 1
  0x3c 16-byte "watermark" (ImageIO writes 'U' ×16; native files carry a
       16-byte trailer instead, duplicated in HEAD)
  0x4c u32 1|3
  0x50 u32 5
FILL  (sparse fill plane; all-zero in emoji samples, small in written files)
ASTC  (u32 byteLen, then 16-byte ASTC 4x4 blocks)
END
```

**Writing ATX on-device (works):** `src/atxwrite.m` uses
`CGImageDestinationCreateWithURL(..., CFSTR("com.apple.atx"), ...)`; ImageIO
emits plain raster 4x4 ASTC blocks (`ceil(w/4) * ceil(h/4)`, 16 B each) and a
`'U'×16` watermark. Decoding round-trips pixel-perfect. The system's gallery
renderer accepts these files.

**Native/server-written ATX** differs: lowercase `astc` tag, block data padded
to 128-px tiles (32×32 blocks), plus a 16-byte trailer at the end of the payload
(identical bytes to the HEAD watermark). The system's tile renderer accepts both.

Gallery thumbnail size for this device: **337×600**. Runtime snapshots:
**1242×2208**.

`src/atx2png.m` decodes ATX via ImageIO (works for our own files, fails on
native twiddled runtime snapshots — their hardware layout is not ImageIO's).

---

## 5. Descriptor / apply path — what actually happens

1. Tapping a gallery item asks PosterBoard to create a poster configuration.
2. PosterBoard resolves a descriptor for the item (`extensionBundleIdentifier`
   + `descriptorIdentifier`), materialises content into
   `configurations/<new-uuid>/versions/0/contents`, renders
   `RuntimeSnapshot-lock/home.atx`, and writes
   `SelectedConfigurationIdentifier.plist`.
3. Observed: the created configurations always contained **native** descriptor
   content (`7365.Green`, `7400.WWDC_2022`), even when the tapped item's
   `descriptorIdentifier` was our slug and `identifier` was our descriptor UUID.
4. `ProviderInfo.plist`'s `kProactiveDynamicPosterDescriptorOrdering` is
   **derived by the daemon** and rewritten on respring; manual UUID appends are
   discarded. Native descriptors are registered; ours are not.

Conclusion: gallery **preview** resolution finds a local descriptor by slug
(that is why our `.atx` art appeared), but **configuration creation** uses the
registered descriptor set. Registering a new descriptor is the open problem.

---

## 6. iOS 16 vs iOS 17 wallpaper formats

iOS 16.7.16 `Wallpaper.plist` types the system renders (observed):

- `LayeredAnimation` — `assets.lockAndHome.default` with
  `backgroundAnimationFileName` / `foregroundAnimationFileName` /
  `floatingAnimationFileNameKey`; each points to a separate `.ca` package.
  Family example: `WWDC22`, `logicalScreenClass: 414w-736h@3x~iphone`.
- `LayeredStripe` (`family: Stripe`), `Bokeh` (`family: Bokeh`), gradients, etc.
- `logicalScreenClass` may be `any` for procedural types.

iOS 16 `.ca` package requirements (from native 7400 layers):

```
index.xml      # rich plist: documentWidth/Height, publishedObjectNames,
               # loopingEnabled, rootDocument, assetManifest, ...
assetManifest.caml
main.caml      # CAML (CoreAnimation XML) document
assets/*.heic|png
```

Native `main.caml` skeleton:

```xml
<caml xmlns="http://www.apple.com/CoreAnimation/1.0">
  <CALayer name="Root Layer" bounds="0 0 414 736" position="207 368"
           geometryFlipped="1">
    <sublayers>
      <CALayer id="Background" name="Background" anchorPoint="0 0"
               bounds="0 0 414 736" position="0 0" geometryFlipped="0">
        <sublayers> ... scene ... </sublayers>
      </CALayer>
    </sublayers>
    <scriptComponents/>
    <states> LKState Locked/Unlock/Sleep </states>
    <stateTransitions> 6 empty LKStateTransition </stateTransitions>
  </CALayer>
</caml>
```

**Tendies packs are iOS 17 format:** one `*.ca` with
`Wallpaper.plist → assets.lockAndHome.default.type = "ParameterizedCA"`,
`family = Marble`, `version = 6`, `contentVersion = 1.07`,
`logicalScreenClass = any`, and a minimal `index.xml`
(only `rootDocument`). Their `main.caml` root carries
`style/wallpaperBackgroundAssetNames` / `wallpaperFloatingAssetNames` /
`wallpaperParallaxGroups` and the layer groups `BACKGROUND` / `FLOATING`
(occasionally `FOREGROUND`) on a 393×852 canvas.

**Decisive fact:** the string `ParameterizedCA` does **not occur anywhere** in
the iOS 16.7.16 dyld cache
(`/private/preboot/Cryptexes/OS/System/Library/Caches/com.apple.dyld/*`),
while `LayeredAnimation` does. 16.7.16 cannot load these packs as shipped.

`tools/convert_tendie.py` (v1) converts a pack into three iOS-16 `.ca`
packages (Background/Foreground/Floating) with the native `index.xml`, a
414×736 root and a "Design Canvas" scale wrapper, and writes a
`LayeredAnimation` `Wallpaper.plist`. It has **not yet been validated** because
the apply path still builds configs from native descriptors (§5).

---

## 7. Tooling (in repo)

| Path | Purpose |
|---|---|
| `src/mal016.m`, `build_mal016.sh` | existing CLI (recon/gestalt/tendie) |
| `src/atxwrite.m`, `build_atxwrite.sh` | PNG/JPEG → ATX via ImageIO (on-device) |
| `src/atx2png.m` | ATX → PNG (our files; native runtime snapshots fail) |
| `src/prstool2.m`, `build_prstool.sh` | PRSService XPC client (fetch/dump/push/additem) |
| `src/prs.entitlements` | entitlement set that makes PRSService accept us |
| `tools/convert_tendie.py` | iOS 17 pack → iOS 16 LayeredAnimation (v1, unvalidated) |
| `research/duet_facegallery_pristine.bin` | clean faceGallery stream copy (revert) |
| `research/snapshot/emoji_snapshot.atx` | native 337×600 ATX sample |
| `packs/` + `fetch_packs.sh` | SerStars/Nugget-Wallpapers catalog + packs |

Build all helpers with the same Linux cross-compile pipeline
(`clang → ld64.lld → ldid`, SDK at `../ABrake27/poc/SDK/iPhoneOS.sdk`).
Deploy binaries to `/var/jb/usr/bin`; sign `prstool2` on-device with the
entitlements file.

Device helper scripts used during the session (PC): `/tmp/ssh_ip.py`,
`/tmp/mal0ssh.py`, `/tmp/mal0s2/scpget.py` (pexpect-based SSH/SCP with the
`thor` password).

---

## 8. Next steps (ordered)

1. **Descriptor registration.** Reverse `PBFPosterExtensionDataStore` /
   `PBFPosterDescriptorStoreCoordinator` in `PosterBoard.framework`
   (`/tmp/pb.dis` was generated with `llvm-objdump --macho -d`) for the
   discovery/reload path, or invoke the data-store XPC
   (`com.apple.posterboardservices.data-store.refreshConfigurations`,
   `refreshConfigurationSnapshot` — entitlements already available).
   Goal: make "apply" build a config from a descriptor we control.
2. **Minimal CA probe.** With (1) solved, install a descriptor whose contents
   are a native-style `.ca` (7400 Background template, one `CALayer` with
   `<contents type="CGImage" src="assets/x.png"/>`, full `index.xml`,
   states/transitions) and verify the lock screen shows the image. This answers
   whether 16 accepts our hand-built CAML.
3. **Converter v2.** Port pack layers (gradient, grass, clouds, character) into
   the validated CAML subset, then animations/state machine.
4. **Productise:** `Mal016 tendie import X.tendies` = normalize pack
   (productTypes/414w-736h/hex UUID) → convert CA → place descriptor →
   generate `.atx` from the pack preview GIF (SerStars `preview` field) →
   push gallery item → respring.

---

## 9. Hygiene / device state

- Revert gallery changes: restore the Duet stream byte copy + `GalleryCache`,
  respring. Verify with `prstool2 fetch` (no `MAL…` items).
- Remove test descriptors (`AAAA016x`) and fake version dirs.
- Do not leave the lock screen on a test configuration.
- Never run unsigned IPA from Telegram (house rule); this project is
  analysis + owner-device experiments only, no exploits.
