# PosterBoard tendies on iOS 16.7.16 — research log (2026-11-08, session 1)

> **STATUS 2026-11-09: this is a historical log. Several conclusions below were
> corrected by sessions 2–5 — see `docs/TENDIES16_MECHANISM.md` (current
> reference) and `HANDOFF.md`.**
>
> Corrections in short:
> - "Gallery ≠ directory scan" — correct, and now fully explained: the gallery
>   is an `ATXFaceGalleryConfiguration` catalog; tiles appear only for items in
>   it. We can now **push items** into that catalog via PRSService XPC with
>   entitlements (see `src/prstool2.m`).
> - "Format compatibility confirmed" — **wrong**. 16.7.16 has no
>   `ParameterizedCA` support at all (string absent from the whole dyld cache);
>   packs are iOS 17 format and need conversion to `LayeredAnimation`.
> - "content-swap did not re-render / RuntimeSnapshotMetadata is the gate" —
>   not the gate; the apply path builds configurations from *registered*
>   descriptors (native ones), not from hand-placed descriptor directories.
> - ProviderInfo ordering is **daemon-derived**: manual UID appends are
>   discarded on respring (verified).

## Confirmed (verified on iPhone10,5 / 16.7.16 20H392, root via Dopamine)
- PosterBoard store: `/var/mobile/Containers/Data/Application/<PB-uuid>/Library/
  Application Support/PRBPosterExtensionDataStore/59/Extensions/<provider>/`
  (**59** on 16.x, not 61 as on 17+).
- Providers on 16.7.16: WallpaperKit.CollectionsPoster, PaperBoard.LegacyPoster,
  EmojiPoster, GradientPoster, PridePoster, UnityPoster, AegirPoster,
  weather.poster, PhotosPosterProvider, WatchFacesWallpaperSupport.
- WallpaperKit.CollectionsPoster serves the lock-screen **Коллекции** (7400.*),
  Clownfish (7420.*) etc. — same `7400.WWDC_2022-414w-736h@3x~iphone.wallpaper`
  CA format the community .tendies packs use. **Format compatibility confirmed.**
- Descriptor anatomy: `<UUID>/com.apple.posterkit.provider.descriptor.identifier`
  (= numeric group id, e.g. 7400) + `versions/<N>/contents/<id>.<name>-<W>w-<H>h@3x~iphone.wallpaper`
  (+ per-device `.ca` layer dirs) + supplements/ + RuntimeSnapshotMetadata-*.plist.
- **Gallery ≠ directory scan**: the "Добавление новых обоев" gallery is an
  ATXFaceGalleryConfiguration (DuetExpertCenter stream `faceGallery`,
  GalleryCache plist). Items are keyed `descriptorIdentifier = "<id>.DYNAMIC"`
  + provider + instance UUID — NOT by on-disk descriptor UUID.
- ProviderInfo.plist of a provider holds `kProactiveDynamicPosterDescriptorOrdering`
  (list of descriptor UUIDs) — registration layer, patched successfully via
  plistlib (NSKeyedArchiver UID append).
- GalleryCache is disposable (rebuilt on respring after purge).
- Packs ship with `productTypes` hardcodes (e.g. iPhone18,3) and 390w-844h
  naming — both must be normalized to the target device (iPhone10,5, 414w-736h).
  Pack UUIDs may be non-hex (5M800000…5QU41R) — must be renamed to valid hex.
- Mulberry: RollingHills pack content = re-packaged native Marble/Lavender
  (identifier 7920) — that's why it looked like a stock duplicate.

## Blocked (open)
- Manually-placed + registered descriptors did NOT appear in the gallery;
  content-swap into a native 7400 descriptor (v81 contents) also did not
  re-render. Rendering likely gated by RuntimeSnapshotMetadata-*.plist and/or
  the PosterBoard/SpringBoard snapshot caches, or the ATX gallery provisioning
  channel itself. Next probes: inspect RuntimeSnapshotMetadata contents,
  posterboard/SpringBoard caches, syslog during gallery build with WallpaperKit
  filter, compare native vs swapped plists byte-level.

## Hygiene
All device modifications were reverted in-session (native descriptor restored
from backup, orphan descriptors removed, ProviderInfo.plist restored to the
original 4-UUID state, caches purged, respring). Backups: /var/tmp/backup_4634
(on device), packs in Mal016/packs/.

## Tooling built
- Mal016 CLI (recon/gestalt/tendie) — cross-compiled on Linux, deployed via
  ssh (usbmuxd+iproxy). Device root password: (redacted).
