# Mal016 HANDOFF — PosterBoard tendies on iOS 16.7.16 (for next AI session)

## Context
Goal: make community `.tendies` wallpaper packs work on iPhone 8+ (iPhone10,5),
iOS 16.7.16 (20H392), jailbroken (Dopamine, root). Owner: Ivan. Tooling: Mal016
CLI (this repo, cross-compiled on Linux, deployed at /var/jb/usr/bin/Mal016).
SSH: USB + `iproxy 2222 22` → root@localhost -p 2222, password: thor.
Helper scripts on PC: /tmp/ssh_ip.py (run cmd via ssh), /tmp/mal0push/*.
Packs: Mal016/packs/ + fetch_packs.sh (SerStars/Nugget-Wallpapers catalog).

## Established facts (see docs/POSTERBOARD_16_RESEARCH.md)
- Store: .../PRBPosterExtensionDataStore/59/Extensions/<provider>/descriptors/
- Target provider: com.apple.WallpaperKit.CollectionsPoster (Коллекции, 7400.*)
- Pack normalization needed: productTypes→['iPhone10,5'], 390w-844h→414w-736h
  (outer .wallpaper dir AND inner *.ca dirs), UUID→valid hex.
- Gallery = ATXFaceGalleryConfiguration (Duet stream faceGallery, cached in
  GalleryCache/*.plist); items keyed '<identifier-file>.DYNAMIC' + provider.
- ProviderInfo.plist kProactiveDynamicPosterDescriptorOrdering = registration
  list (patchable via python plistlib, NSKeyedArchiver, UID append).

## Blocked at
Descriptors placed + registered did not appear in gallery; content-swap into
native 7400 v81 contents did not re-render either. Suspects (in order):
1. **RuntimeSnapshotMetadata-lock/home.plist** in descriptor versions/<N>/ —
   likely pre-rendered snapshot refs the system trusts instead of contents.
2. SpringBoard/posterboard snapshot caches outside the store.
3. ATX gallery provisioning only trusts MobileAsset-delivered descriptors.

## Next probes
- Pull RuntimeSnapshotMetadata-*.plist from native 7400 descriptor
  (46349938-3F6F-4333-9329-7A10BDA4AFDE/versions/78..81) and from a pack;
  diff structure (they are binary plists).
- idevicesyslog filtered 'WallpaperKit|PosterKit|snapshot|PaperBoard' while
  opening gallery.
- Check /var/mobile/Library/Caches/... PosterBoard/SpringBoard poster caches.
- Alternative path: PaperBoard.LegacyPoster (older engine) — its descriptors
  dir is empty; maybe 16.x still instantiates LegacyPoster for custom CA.
- Rollback: native 46349938 backup at device /var/tmp/backup_4634; original
  ProviderInfo in PC /tmp/pbpull/wk_provider.plist.

## Hygiene rules (from project scope)
Static analysis and device- owner experiments only; no exploit development;
revert device state after experiments; logs must carry RECON identity.

## Session-1 late addendum (same day)
- Native 46349938 has versions 78-81 but ONLY v81 has contents/ (others empty).
  Swapping contents in ALL versions did NOT change the gallery tile art.
- Purged MappedImageCache/Wallpaper + WallpaperColorBoxesCache + GalleryCache —
  no effect on tile rendering. Tile thumbnails are NOT rendered live from
  contents/ on 16.7.16.
- Distinctive file: native contents contain
  `com.apple.posterkit.provider.contents.galleryOptions`; packs ship
  `...otherMetadata.plist` instead. Candidate gate.
- Device RESTORED to pristine state (4 native descriptors verified, caches
  cleared, ProviderInfo original). SuperMarioBros_fixed.tendies (productTypes
  patched) remains in Media + PC /tmp/mal0push/.
- Next session top probes: (1) diff native vs pack Wallpaper.plist +
  galleryOptions vs otherMetadata semantics (pull both, plistlib);
  (2) grep PaperBoard/WallpaperKit binaries in dyld cache for
  galleryOptions/ATXFaceGallery keys; (3) idevicesyslog during gallery open
  filtered 'ATX|PaperBoard|snapshot|thumbnail'; (4) check whether tile art
  comes from Duet faceGallery preview assets, not the store.

## Session-1 final addendum (post-mortem of probes)
- Native per-descriptor `com.apple.posterkit.provider.contents.galleryOptions`
  = ATXPosterDescriptorGalleryOptions (localizedTitle 'Коллекции', hero flag,
  complications flags). Packs carry `otherMetadata` instead → cloned native
  galleryOptions with custom title for Mario — still no tile.
- Duet stream `/var/mobile/Library/DuetExpertCenter/streams/faceGallery/local/
  815610501801543` (8MB binary, device-scoped header, contains 7400.DYNAMIC ×40
  and native instance UUIDs ×3) — patched equal-length (B18666BC→5D800000 ×3) —
  still no tile. Rolled back.
- syslog during gallery open: NO CollectionsPoster process spawn at all; only
  PhotosPosterProvider XPC. The gallery UI never touches foreign descriptors.
- **Conclusion:** tile art/rows are provisioned through a channel that only
  accepts descriptors registered in a trust store not yet located. Top
  hypothesis: MobileAsset asset audit (com.apple.mobileassetd) or a PosterKit
  SQLite/plist index inside SpringBoard container.
- **Next session = binary RE (ABrake27 home turf):** extract
  WallpaperKit/WallpaperFoundation/PaperBoard + PosterKit-related dylibs from
  16.7.16 dyld cache (extracted_16716/ available, 479MB), grep for
  ATXFaceGalleryItem/descriptorIdentifier/galleryOptions resolution, find the
  trust check that gates foreign descriptors. Diff against 17.x would also
  reveal what Nugget exploits.
- Device state: fully pristine (Duet restored, descriptors removed, caches
  purged). PC artifacts: /tmp/rsn/* (native galleryOptions/userInfo/Duet
  backup), /tmp/pbpull/*, /tmp/mal0push/* scripts.

## Session-1 CONCLUSION (binary RE pass, same day)
- Extracted from 16.7.16 dyld cache: PosterKit (1.8MB), PosterBoard (2.4MB),
  PosterBoardServices (527KB) → mcm_research/pb16716/.
- PosterBoardServices disasm reveals the mechanism: **PRSServer** with
  fetchGallery / retrieveGallery / pushPosterGalleryUpdate /
  loadGalleryOptionsWithError / storeGalleryOptions — **the lock-screen
  gallery catalog is SERVER-FETCHED**. Local descriptor placement cannot add
  gallery tiles: tiles appear only when the server catalog references them.
  This conclusively explains why Nugget needs iOS 17+ (different local
  mechanism there) and why all our local-side injections failed.
- Local attack/extension surface identified (research note only):
  `com.apple.posterboardservices.data-store.*` XPC methods
  (deleteDescriptors / refreshConfigurations / refreshConfigurationSnapshot /
  mutateSwitcherConfiguration / deleteDataStore / migration) +
  `PRSService notifyPosterBoardOfApplicationUpdates` — unauthenticated
  local XPC into the poster data store is a plausible content-injection
  vector on 16.x. NOT developed (scope line); flagging for future audit.
- Practical workaround remains: WallpaperKit content-SWAP of an installed
  descriptor works mechanically (files land fine) but rendered tile did not
  change even after MappedImageCache/ColorBoxesCache/GalleryCache purge —
  rendering likely uses per-instance snapshots keyed by the SERVER instance
  UUIDs (B18666BC-style), not on-disk UUIDs. Revisit only with a full
  PaperBoard render-pipeline RE.

## Session-1 night addendum (black-box exhausted)
- Searched /var/mobile/Library, SystemGroup, Preferences, AppGroups for ANY
  reference to native descriptor UUID (0A314BD1…) — **zero hits outside the
  Duet stream**. Wallpaper assignment state is not stored in user-space files
  we can find; likely inside SpringBoard's real data container (identify via
  bundle scan, not SplashBoard) or a daemon-private store.
- SpringBoard container found at 014419A3-… was the SplashBoard app (wrong).
  Identify real SB data container via /var/containers/Bundle/Application
  SpringBoard.app bundle-id match next time.
- **Next session = full RE pass (Ghidra/pyghidra):** PosterKit (1.8MB) +
  PosterBoardServices (527KB) already extracted in
  ABrake27/mcm_research/pb16716/. Targets: (1) PRSServer fetchGallery → where
  server catalog is persisted and how items resolve to disk contents;
  (2) PRPoster instance creation from ATXFaceGalleryItem; (3) any
  entitlement/trust check gating descriptor adoption.

## Session-1 late-night: THE missing link located
- `configurations/<uuid>/identifierURL.suggestionMetadata.plist` =
  PRPosterSuggestionMetadata{ATXFaceGalleryItem} — these are the SYSTEM'S
  OUTPUT of provisioning (storeSuggestionMetadataForPath:), not input.
- The Duet stream (faceGallery/local/815610501801543, 8MB) = **the gallery
  catalog itself**: fixed-size-ish records (~2.1KB) of
  [variant-UUID][identifier e.g. 7400.DYNAMIC][provider][...fields], header
  0x165e8 (count/offsets). 40 records for 7400.DYNAMIC across variants.
- Full chain now known: server catalog → Duet stream → GalleryCache → tiles.
  To add a tile: INSERT a record into the stream (requires parsing the record
  layout: header counts + per-record TLV) AND place a matching descriptor in
  the store (normalization: productTypes, 414w names, hex UUID, galleryOptions).
- Repro assets on PC: /tmp/rsn/duet_facegallery(.bak) (8MB stream),
  /tmp/rsn/native_galleryOptions, /tmp/rsn/wk_sugg.plist (cloned native item),
  /tmp/rsn/mario_galleryOptions; device: /var/tmp/mz (unpacked mario),
  /var/tmp/go_mario. Device currently has our descriptor 5D800000 + our
  configuration 11111111-… (harmless; remove when done: rm -rf those dirs,
  restore ProviderInfo from /tmp/pbpull/wk_provider.plist).
- Streams to reverse next: Duet record format (start: hexdump first 2 records,
  find count field at header, diff records of same provider to get field map).

## Session-1 protobuf breakthrough (final)
- Duet stream = **protobuf wire format**, 844 gallery items, fixed 8MiB alloc,
  header: u32 LE 91624 (used-length?) + u32 0 + 8-byte timestamp; records
  start at 0x60.
- Record shape: optional `08 <section-varint>` prefix, then `12 <len> <item>`;
  item = protobuf {1: variant-UUID (36B), 2: '<id>.DYNAMIC|STATIC',
  3: provider-bundle-id, ...more fields}. 844 uuid-field matches confirm.
- Parser progress: clean parse from 0x60 breaks at 0x2da (6 records) —
  remaining fields (score? layout? sections?) need a full field-map walk.
  Next: parse ALL items with per-item field walk (tolerate unknown wt),
  build field map by frequency, then write record generator + insertion
  (shift tail, bump header u32) → tile in gallery.
- This is the FINAL gate: everything else (descriptor placement,
  normalization, registration, galleryOptions) is already solved and scripted.

## Session-1 FINAL VERDICT
- Duet stream patch PERSISTS (not server-reverted, verified 60s+ after write,
  no respring) — so server sync is NOT the gate.
- Full stack deployed simultaneously (patched stream + descriptor +
  configuration + ProviderInfo registration + caches purged) — still no tile.
- Nested structure observed: protobuf field1 at top level contains ANOTHER
  protobuf message with the same item UUID inside → items live at depth ≥2,
  and there are likely per-item additional nested fields (instance records?)
  the naive leaf swap missed.
- **Device fully restored to pristine** (Duet from backup, descriptor/config
  removed, ProviderInfo original 4-UUID, respring). Backups on device:
  /var/tmp/duet_backup, /var/tmp/backup_4634.
- **Next session (fresh context), single focused task:** recursive protobuf
  parser of the Duet stream (depth ≥2, collect leaf items + their full
  serialized envelopes), build complete record field map (844 items), THEN
  generate a fully-formed record set (all nesting levels), insert, test.
  Fallback: Ghidra on PosterKit PRSServer fetchGallery to see what the server
  response schema is — the stream is its local persistence.
- Repro assets: PC /tmp/rsn/*, /tmp/pbpull/*, /tmp/mal0push/*; device
  /var/tmp/{mz,go_mario,duet_backup,backup_4634}; packs in Mal016/packs/.

## Session-1 external intel (final)
- **Tendies16** — WIP jailbreak tweak (r/jailbreak post "PosterBoard for iOS 16",
  id 1vul8kb), imports .tendies on iOS 16. No repo/public release yet.
  WATCH: when released, reverse its mechanism immediately — it solves the
  exact tile-registration problem we mapped. Reddit JSON blocked from PC;
  use different UA/proxy or check manually.
- Everything else (Nugget/Pocket-Poster/Cowabunga) = iOS 17+ only.

## Session-1 CLOSE: instance registry + content-on-demand = FINAL ANSWER
- **PosterConfigurationCache** (single file, /var/mobile/Library/DuetExpertCenter/)
  = NSKeyedArchiver array of ATXPosterConfiguration records: {posterUUID =
  configuration-folder UUID, galleryItem = ATXFaceGalleryItem embed,
  extensionBundleIdentifier, font, active, selected, complications}. THIS is
  the instance registry (9 records = current lock-screen wallpaper slots).
- Key finding: configuration 0FE734F1 references descriptor identifier
  7DBF540C that has **ZERO bytes on disk** (global /var search). Poster
  content is fetched from the server ON SELECTION. The gallery catalog is
  fully server-centric on iOS 16.x: local descriptor placement cannot create
  tiles, and installed-poster content lives nowhere locally until used.
- **Conclusion (high confidence):** on iOS 16.x, third-party tendies via the
  PosterBoard pipeline require impersonating the server provisioning flow
  (MITM of the gallery fetch / asset download) — no local-only injection
  path exists. This is why Tendies16 (WIP) must be doing something else
  entirely (likely rendering its own posters outside PosterKit, or hijacking
  the extension). When it ships — reverse immediately.
- Device PRISTINE (registry, ProviderInfo, descriptors, configurations,
  caches all restored; respring done). All backups intact.
